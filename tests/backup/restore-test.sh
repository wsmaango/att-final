#!/usr/bin/env bash
# 복구 리허설: mon01 의 최신 덤프를 data01 의 임시 DB(att_restore_test)로 복원하고,
# 고객사별 출근 기록 건수가 덤프 시점 원본과 맞는지 비교한다. RPO·RTO 를 같이 출력한다.
#
# mon01 에서 backup-att 사용자로 실행 (덤프 폴더 권한 700, .pgpass 가 그 사용자에게 있음):
#   sudo -u backup-att bash /tmp/restore-test.sh <data01 사설 IP>
# 작업 VM 에서 한 번에:
#   scripts/ev.sh 6-restore 'scp -q -P 2206 tests/backup/restore-test.sh ubuntu@$MGMT:/tmp/ && ssh -p 2206 ubuntu@$MGMT "sudo -u backup-att bash /tmp/restore-test.sh 192.168.0.30"'
#
# RPO(최악) = 백업 주기 15분 + 덤프 소요 시간. 이번 측정값 = 지금 - 최신 덤프 시각
# RTO      = 이 스크립트의 복원 시간 + 앱이 새 DB 를 보게 바꾸는 시간(DB_HOST/DB_NAME 변경 + 재시작)
set -euo pipefail
DATA_IP=${1:?data01 사설 IP}
cd /tmp   # backup-att 는 호출한 사용자의 홈에 들어갈 수 없다
latest=$(ls -1t /var/backups/att/att-*.dump 2>/dev/null | head -1 || true)
[ -n "$latest" ] || { echo "덤프 파일이 없습니다"; exit 1; }
dump_epoch=$(stat -c %Y "$latest")
echo "latest dump : $latest ($(date -d @"$dump_epoch" '+%F %T %Z'), $(stat -c %s "$latest") bytes)"
echo "dump age    : $(( $(date +%s) - dump_epoch )) s  (= 지금 장애가 나면 잃는 최대 구간, RPO 실측)"

pg_restore --list "$latest" > /dev/null || { echo "덤프를 읽을 수 없습니다 (깨진 파일)"; exit 1; }

t0=$(date +%s)
dropdb   -h "$DATA_IP" -U att --maintenance-db=att --if-exists att_restore_test
createdb -h "$DATA_IP" -U att --maintenance-db=att att_restore_test
pg_restore -h "$DATA_IP" -U att -d att_restore_test --no-owner --no-privileges --exit-on-error "$latest"
t1=$(date +%s)

# pg_hba 는 att 에게 att·att_restore_test 만 열어 두었으므로 createdb/dropdb 도 att DB 를 거쳐 접속한다
# 임시 DB 에서만 FORCE RLS 를 풀어 전체 건수를 센다 (운영 DB 는 건드리지 않는다)
psql -h "$DATA_IP" -U att -d att_restore_test -q -c "ALTER TABLE attendance NO FORCE ROW LEVEL SECURITY; ALTER TABLE employees NO FORCE ROW LEVEL SECURITY;"
q="SELECT tenant_id, count(*) FROM attendance WHERE ts <= to_timestamp(${dump_epoch}) GROUP BY 1 ORDER BY 1"
restored=$(psql -h "$DATA_IP" -U att        -d att_restore_test -tA -F' ' -c "$q")
source_=$(psql  -h "$DATA_IP" -U att_backup -d att              -tA -F' ' -c "$q")
emp=$(psql -h "$DATA_IP" -U att -d att_restore_test -tA -c "SELECT count(*) FROM employees")

echo "--- 고객사별 출근 기록 (덤프 시각 이전 기준): 원본 | 복원"
paste -d'|' <(echo "$source_") <(echo "$restored") | sed 's/|/  |  /'
echo "employees(복원): $emp"
if [ "$source_" = "$restored" ]; then echo "일치: 예"; else echo "일치: 아니오"; fi
echo "restore_seconds=$(( t1 - t0 ))"
dropdb -h "$DATA_IP" -U att --maintenance-db=att att_restore_test
echo "임시 DB 삭제 완료"
[ "$source_" = "$restored" ]

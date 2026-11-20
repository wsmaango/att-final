#!/usr/bin/env bash
# S1 상황 B 의 "출근 기록 유실 0" 검증.
# measure.sh(MODE=clock) 로그에서 접수 성공(200·201·202)한 사원번호를 모아, data01 DB 에 오늘 출근 기록이 있는지 센다.
# 사용 (본인 PC, 스풀이 비워진 뒤 = Grafana 에서 att_spool_pending 0 확인 후):
#   tests/failover/verify-no-loss.sh evidence/s1-b.log <mgmt_ip> [tenant_id=1] [data01 ssh 포트=2205]
set -euo pipefail
LOG=${1:?measure.sh 로그}; MGMT=${2:?mgmt_ip}; TENANT=${3:-1}; PORT=${4:-2205}
emps=$(grep -v '^#' "$LOG" | awk -F, '$2==200||$2==201||$2==202 {print $5}' | sort -u)
n=$(echo "$emps" | grep -c . || true)
[ "$n" -eq 0 ] && { echo "접수 성공 건이 없습니다 (MODE=clock 로그인지 확인)"; exit 1; }
in_list=$(echo "$emps" | sed "s/.*/'&'/" | paste -sd, -)
sql="SELECT count(DISTINCT emp_no) FROM attendance WHERE tenant_id=${TENANT} AND kind='in' AND work_date=(now() AT TIME ZONE 'Asia/Seoul')::date AND emp_no IN (${in_list});"
found=$(echo "$sql" | ssh -p "$PORT" "ubuntu@${MGMT}" "sudo -u postgres psql -d att -tA")
spooled=$(echo "SELECT count(*) FROM attendance WHERE tenant_id=${TENANT} AND source='spool' AND work_date=(now() AT TIME ZONE 'Asia/Seoul')::date;" | ssh -p "$PORT" "ubuntu@${MGMT}" "sudo -u postgres psql -d att -tA")
echo "접수 성공 사원 수(로그): ${n}"
echo "DB 에 기록된 사원 수:     ${found}"
echo "그중 스풀 재적재(오늘):   ${spooled}"
echo "유실: $(( n - found ))건"
[ "$found" -eq "$n" ]

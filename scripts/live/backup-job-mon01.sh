#!/usr/bin/env bash
# mon01 에서 실행 (root). 백업 작업을 att_backup 역할로 바꾸고, 실패 시 깨진 파일을 남기지 않게 한다.
# 첫 두 줄로 DBPW=<비밀번호>, DATA_IP=<data01 사설 IP> 를 받는다. (mon.sh 의 같은 부분과 내용이 같아야 한다)
set -euo pipefail
: "${DBPW:?}" "${DATA_IP:?}"
cat > /home/backup-att/.pgpass <<CONF
${DATA_IP}:5432:att:att_backup:${DBPW}
${DATA_IP}:5432:*:att:${DBPW}
CONF
chown backup-att:backup-att /home/backup-att/.pgpass && chmod 600 /home/backup-att/.pgpass
cat > /usr/local/bin/att-backup.sh <<CONF
#!/usr/bin/env bash
set -euo pipefail
cd /   # 수동 실행 시 호출한 사용자의 폴더에 권한이 없어 find 가 실패하던 문제 (6단계)
ts=\$(date +%Y%m%dT%H%M%S)
tmp=/var/backups/att/.att-\$ts.dump.part
trap 'rm -f "\$tmp"' EXIT
# att_backup: 읽기 전용 + BYPASSRLS (앱 계정 att 는 FORCE RLS 때문에 덤프가 실패한다)
pg_dump -h ${DATA_IP} -U att_backup -Fc att > "\$tmp"
pg_restore --list "\$tmp" > /dev/null          # 읽을 수 있는 덤프인지 확인
mv "\$tmp" /var/backups/att/att-\$ts.dump       # 성공한 것만 이름을 붙인다
find /var/backups/att -name 'att-*.dump' -mtime +7 -delete
echo "att_backup_last_success_timestamp \$(date +%s)" > /var/lib/prometheus/node-exporter/att_backup.prom.tmp
mv /var/lib/prometheus/node-exporter/att_backup.prom.tmp /var/lib/prometheus/node-exporter/att_backup.prom
CONF
chmod 755 /usr/local/bin/att-backup.sh
echo "updated /usr/local/bin/att-backup.sh"

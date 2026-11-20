#!/usr/bin/env bash
# 복구 리허설: mon01 의 최신 덤프를 data01 의 임시 DB 로 복원하고 RTO 를 잰다.
# mon01 에서 실행. RPO = 장애 시각 - 최신 덤프 시각, RTO = 이 스크립트 소요 시간 + 앱 전환 시간
set -euo pipefail
DATA_IP=${1:?data01 사설 IP}
latest=$(ls -1t /var/backups/att/att-*.dump | head -1)
echo "latest dump: $latest ($(stat -c %y "$latest"))"
t0=$(date +%s)
sudo -u backup-att createdb -h "$DATA_IP" -U att att_restore_test 2>/dev/null || true
sudo -u backup-att pg_restore -h "$DATA_IP" -U att -d att_restore_test --clean --if-exists "$latest"
sudo -u backup-att psql -h "$DATA_IP" -U att -d att_restore_test -c "SELECT count(*) AS reservations FROM reservations;"
echo "restore_seconds=$(( $(date +%s) - t0 ))"

#!/usr/bin/env bash
# 장애 주입 중 요청을 0.2초 간격으로 보내고, 실패 구간 길이(=체감 중단 시간)를 계산한다.
# 사용: MODE=clock ./measure.sh https://<service_ip> 120 > evidence/failover-$(date +%H%M).log
#   MODE=clock : POST /api/clock (200·201·202 = 성공. 202 는 DB 장애 중 스풀 접수)
#   MODE=today : GET  /api/attendance/today (200 = 성공)
# 다른 터미널에서 장애 주입 (예: ssh -p 2203 ... 'sudo systemctl stop att-app')
set -uo pipefail
BASE=${1:?https://service_ip}; DURATION=${2:-120}; MODE=${MODE:-clock}
KEY=${API_KEY:-demo-key-tenant-1}
end=$(( $(date +%s) + DURATION ))
fail_start=""; total_fail_ms=0; n=0; nfail=0; nspool=0
echo "# ts_ms,code,time_total,served_by,emp_no"
while [ "$(date +%s)" -lt "$end" ]; do
  now=$(date +%s%3N)
  if [ "$MODE" = clock ]; then
    emp=$(printf 'E%04d' $(( RANDOM % 20000 + 1 )))
    out=$(curl -sk -o /dev/null -m 2 -D - -w '%{http_code} %{time_total}' -XPOST \
      -H "X-Api-Key: $KEY" -H 'Content-Type: application/json' -d "{\"emp_no\":\"$emp\",\"kind\":\"in\"}" "$BASE/api/clock" 2>/dev/null)
  else
    emp="-"
    out=$(curl -sk -o /dev/null -m 2 -D - -w '%{http_code} %{time_total}' -H "X-Api-Key: $KEY" "$BASE/api/attendance/today" 2>/dev/null)
  fi
  code=$(echo "$out" | tail -1 | cut -d' ' -f1); t=$(echo "$out" | tail -1 | cut -d' ' -f2)
  by=$(echo "$out" | grep -i '^x-served-by' | tr -d '\r' | cut -d' ' -f2)
  echo "$now,$code,$t,$by,$emp"
  n=$((n+1)); [ "$code" = 202 ] && nspool=$((nspool+1))
  case "$code" in
    200|201|202) [ -n "$fail_start" ] && { total_fail_ms=$(( total_fail_ms + now - fail_start )); fail_start=""; } ;;
    *) nfail=$((nfail+1)); [ -z "$fail_start" ] && fail_start=$now ;;
  esac
  sleep 0.2
done
[ -n "$fail_start" ] && total_fail_ms=$(( total_fail_ms + $(date +%s%3N) - fail_start ))
echo "# mode=$MODE requests=$n failed=$nfail spooled=$nspool success_rate=$(awk "BEGIN{printf \"%.3f\", 100*($n-$nfail)/$n}")% downtime_ms=$total_fail_ms" >&2

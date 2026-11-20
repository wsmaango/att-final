#!/usr/bin/env bash
# Prometheus 쿼리 결과를 텍스트로 (Grafana 캡처 대신 쓰는 SLI 증거). ev.sh 와 같이 쓴다.
# 사용: PROM=http://<mgmt_ip>:9090 scripts/promq.sh 'att:clock_p95_seconds:5m'
#       scripts/ev.sh s5-sli 'scripts/promq.sh "1 - att:error_ratio:5m"'
set -euo pipefail
PROM=${PROM:?PROM=http://<mgmt_ip>:9090 을 먼저 export}
Q=${1:?PromQL}
curl -sG "$PROM/api/v1/query" --data-urlencode "query=$Q" \
  | jq -r --arg q "$Q" '"query: \($q)", (.data.result[] | "\(.metric | del(.__name__) | tostring)  \(.value[1])"), (if (.data.result|length)==0 then "(결과 없음)" else empty end)'

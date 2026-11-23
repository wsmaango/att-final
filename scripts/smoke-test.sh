#!/usr/bin/env bash
# 배포 직후·재생성 후 동작 확인. 사용: scripts/smoke-test.sh <service_ip>
set -euo pipefail
IP=${1:?service_ip}; B="https://${IP}"
# 키는 ~/.att-env 의 ATT_KEY_T1·T2 에서 읽는다 (S4: 키를 저장소에 두지 않음). 없으면 데모 키.
[ -f ~/.att-env ] && source ~/.att-env
K1="X-Api-Key: ${ATT_KEY_T1:-demo-key-tenant-1}"; K2="X-Api-Key: ${ATT_KEY_T2:-demo-key-tenant-2}"
J='Content-Type: application/json'; ok=0; fail=0
code() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }
t() { if [ "$2" = "$3" ]; then echo "PASS  $1"; ok=$((ok+1)); else echo "FAIL  $1 (expected $3, got $2)"; fail=$((fail+1)); fi; }
# 고객사 2 에 기록이 없는 사번을 고른다. 부하 테스트(k6)가 같은 사번 범위를 무작위로 쓰기 때문에,
# 아무 사번이나 고르면 고객사 2 의 "자기" 기록이 보여 분리 실패로 오판한다 (5단계에서 실제로 발생).
for _ in $(seq 1 30); do
  EMP=$(printf 'E%04d' $(( RANDOM % 20000 + 1 )))
  [ "$(curl -sk -H "$K2" ${B}/api/employees/${EMP}/records)" = "[]" ] && break
done
t "HTTP → HTTPS 301"         "$(code http://${IP}/)" 301
t "readyz 200 (DB 연결)"      "$(code ${B}/readyz)" 200
t "키 없으면 401"             "$(code -XPOST -H "$J" -d '{"emp_no":"E0001"}' ${B}/api/clock)" 401
t "출근 201 또는 200(중복)"   "$(code -XPOST -H "$K1" -H "$J" -d "{\"emp_no\":\"$EMP\",\"kind\":\"in\"}" ${B}/api/clock | sed 's/^201$/200/')" 200
t "같은 출근 재요청 200(멱등)" "$(code -XPOST -H "$K1" -H "$J" -d "{\"emp_no\":\"$EMP\",\"kind\":\"in\"}" ${B}/api/clock)" 200
t "현황 200"                  "$(code -H "$K1" ${B}/api/attendance/today)" 200
t "다른 고객사에서는 기록 안 보임" "$(curl -sk -H "$K2" ${B}/api/employees/${EMP}/records)" "[]"
n=$(for i in $(seq 20); do curl -sk -D - -o /dev/null ${B}/readyz | grep -i x-served-by; done | sort -u | wc -l)
t "두 app 노드가 모두 응답" "$([ "$n" -ge 2 ] && echo yes || echo no)" yes
echo "pass=$ok fail=$fail"; [ "$fail" -eq 0 ]

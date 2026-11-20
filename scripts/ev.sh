#!/usr/bin/env bash
# 실행 결과를 증거 파일로 남긴다. 화면에도 그대로 보이고, 파일에는 공인 IP 를 가려 저장한다.
# 사용: scripts/ev.sh <이름> '<명령>'
#   scripts/ev.sh s1-validate 'terraform -chdir=terraform validate'
#   scripts/ev.sh s2-ufw-app01 'ssh -p 2203 ubuntu@$MGMT "sudo ufw status numbered"'
# 저장 위치: evidence/<날짜-시각>-<이름>.txt  (명령, 시각, 호스트, 출력, 종료 코드)
set -uo pipefail
NAME=${1:?이름}; shift
CMD="$*"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/evidence"
OUT="$ROOT/evidence/$(date +%Y%m%d-%H%M%S)-${NAME}.txt"
TMP=$(mktemp)

{
  echo "# command : $CMD"
  echo "# time    : $(date -Is)"
  echo "# host    : $(hostname)   cwd: $PWD"
  echo
} > "$TMP"

bash -o pipefail -c "$CMD" 2>&1 | tee -a "$TMP"
RC=${PIPESTATUS[0]}
printf '\n# exit    : %s\n' "$RC" >> "$TMP"

# 사설 대역(10/8, 172.16/12, 192.168/16, 127/8)이 아닌 IPv4 는 x.x.x.x 로 가린다
perl -pe 's/\b(?!(?:10|127)\.)(?!192\.168\.)(?!172\.(?:1[6-9]|2\d|3[01])\.)(?:\d{1,3}\.){3}\d{1,3}\b/x.x.x.x/g' "$TMP" > "$OUT"
rm -f "$TMP"
echo "→ 저장: ${OUT#$ROOT/}"
exit "$RC"

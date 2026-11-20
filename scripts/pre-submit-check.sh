#!/usr/bin/env bash
# 제출 직전 점검 + zip 생성. 사용: scripts/pre-submit-check.sh 32xxxxxx 홍길동
set -uo pipefail
cd "$(dirname "$0")/.."
SID=${1:?학번}; NAME=${2:?이름}; ZIP="../${SID}_${NAME}_최종과제.zip"; bad=0
echo "== 1. 금지 파일"
found=$(find . \( -name '.terraform' -o -name '*.tfstate*' -o -name '*.tfvars' -o -name '.env' -o -name '*.pem' -o -name '*.key' -o -name 'id_*' -o -name 'kubeconfig*' -o -name 'node_modules' \) -not -name '*.example' -not -path './.git/*')
[ -n "$found" ] && { echo "$found"; echo "→ zip 에서 제외됩니다. 저장소 이력에도 없는지 확인"; }
echo "== 2. 시크릿 스캔"
if command -v gitleaks >/dev/null; then gitleaks detect --source . -v --log-opts="--all" || bad=1
else echo "gitleaks 미설치 → 간이 검사"; grep -rInE "(api[_-]?key|secret[_-]?key|password)\s*[:=]\s*['\"]?[A-Za-z0-9/+]{12,}" --exclude-dir=.git --exclude-dir=.terraform . | grep -v -E "CHANGE_ME|DUMMY|TODO|example" && bad=1; fi
echo "== 3. 리포트 TODO 남은 개수"; grep -c "TODO" docs/REPORT.md
echo "== 4. REPORT.pdf 존재"; [ -f docs/REPORT.pdf ] && echo ok || { echo "없음"; bad=1; }
echo "== 5. terraform fmt"; (cd terraform && terraform fmt -check -recursive) || bad=1
[ "$bad" -ne 0 ] && { echo "문제를 고친 뒤 다시 실행하세요"; exit 1; }
zip -r "$ZIP" . -x '.git/*' '*/.terraform/*' '*.tfstate*' '*.tfvars' '.env' '*.pem' '*.key' 'node_modules/*' '*.zip' >/dev/null
echo "생성: $ZIP"

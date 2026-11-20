#!/usr/bin/env bash
# 고객사 API 키 교체 (S4 대응). data01 에서 실행. 새 키는 화면에 한 번만 출력되고 DB 에는 해시만 남는다.
# 사용: sudo scripts/rotate-tenant-key.sh <tenant_id>
# 앱의 고객사 캐시(TENANT_CACHE_TTL=30초)가 지나면 예전 키는 401 이 된다 → 이 시간을 S4 에서 측정한다.
set -euo pipefail
TID=${1:?tenant_id}
NEW_KEY="att_$(openssl rand -hex 24)"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d att -c \
  "UPDATE tenants SET api_key_hash = encode(sha256(convert_to('${NEW_KEY}', 'UTF8')), 'hex') WHERE id = ${TID};" >/dev/null
echo "tenant ${TID} rotated at $(date -Is)"
echo "new key (고객사에 안전한 채널로 전달, 저장소·캡처에 남기지 말 것): ${NEW_KEY}"

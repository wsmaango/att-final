#!/usr/bin/env bash
# data01 에서 실행 (root). 백업 전용 역할 att_backup 을 만든다. 첫 줄로 DBPW=<비밀번호> 를 받는다.
# 왜: 앱 테이블은 FORCE ROW LEVEL SECURITY 라 소유자(att)로 pg_dump 하면 RLS 오류로 실패한다.
#     att 에 BYPASSRLS 를 주거나 FORCE 를 빼면 고객사 분리가 약해지므로, 읽기 전용 + BYPASSRLS 인
#     별도 역할을 mon01 IP 에서만 접속하게 둔다. (data.sh 의 같은 부분과 내용이 같아야 한다)
set -euo pipefail
: "${DBPW:?}" "${MON_IP:=192.168.0.40}"
PGCONF=/etc/postgresql/$(ls /etc/postgresql | sort -V | tail -1)/main
grep -q ' att_backup ' $PGCONF/pg_hba.conf || echo "host att att_backup ${MON_IP}/32 scram-sha-256" >> $PGCONF/pg_hba.conf
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
SELECT 'CREATE ROLE att_backup LOGIN BYPASSRLS' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'att_backup')\gexec
ALTER ROLE att_backup PASSWORD '${DBPW}';
GRANT CONNECT ON DATABASE att TO att_backup;
\c att
GRANT USAGE ON SCHEMA public TO att_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO att_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO att_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE att IN SCHEMA public GRANT SELECT ON TABLES TO att_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE att IN SCHEMA public GRANT SELECT ON SEQUENCES TO att_backup;
SQL
systemctl reload postgresql
sudo -u postgres psql -tAc "SELECT rolname, rolbypassrls, rolsuper, rolcreatedb FROM pg_roles WHERE rolname='att_backup'"
grep ' att_backup ' $PGCONF/pg_hba.conf

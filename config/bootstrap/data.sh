#!/usr/bin/env bash
# data: PostgreSQL + Redis(W5 Part 2 보안 설정). 앱 노드와 백업(mon)에서만 접근
set -euxo pipefail
source /etc/att/bootstrap.env

apt-get install -y postgresql redis-server

# --- Redis: 사설 IP + 루프백 바인딩, requirepass ---
sed -i "s/^bind .*/bind 127.0.0.1 ${SELF_IP}/" /etc/redis/redis.conf
sed -i "s/^# *requirepass .*/requirepass ${REDIS_PASSWORD}/" /etc/redis/redis.conf
grep -q '^requirepass' /etc/redis/redis.conf || echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
sed -i 's/^# *maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
grep -q '^maxmemory-policy' /etc/redis/redis.conf || echo 'maxmemory-policy allkeys-lru' >> /etc/redis/redis.conf
systemctl enable redis-server
systemctl restart redis-server

# --- PostgreSQL ---
PGVER=$(ls /etc/postgresql | sort -V | tail -1)
PGCONF=/etc/postgresql/${PGVER}/main
sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost,${SELF_IP}'/" ${PGCONF}/postgresql.conf
for ip in ${APP_IPS} ${MON_IP}; do
  grep -q "${ip}/32" ${PGCONF}/pg_hba.conf || echo "host att,att_restore_test att ${ip}/32 scram-sha-256" >> ${PGCONF}/pg_hba.conf
done
systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'att') THEN
    CREATE ROLE att LOGIN CREATEDB PASSWORD '${DB_PASSWORD}';
  END IF;
END \$\$;
SQL
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='att'" | grep -q 1 \
  || sudo -u postgres createdb -O att att

# --- 백업 전용 역할 (6단계에서 추가, scripts/live/backup-role-data01.sh 와 같은 내용) ---
# 앱 테이블은 FORCE ROW LEVEL SECURITY 라 소유자(att)로 pg_dump 하면 RLS 오류로 실패한다.
# att 를 약하게 만들지 않고, 읽기 전용 + BYPASSRLS 역할을 mon01 에서만 쓰게 한다.
grep -q ' att_backup ' ${PGCONF}/pg_hba.conf || echo "host att att_backup ${MON_IP}/32 scram-sha-256" >> ${PGCONF}/pg_hba.conf
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
SELECT 'CREATE ROLE att_backup LOGIN BYPASSRLS' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'att_backup')\\gexec
ALTER ROLE att_backup PASSWORD '${DB_PASSWORD}';
GRANT CONNECT ON DATABASE att TO att_backup;
\\c att
GRANT USAGE ON SCHEMA public TO att_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO att_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO att_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE att IN SCHEMA public GRANT SELECT ON TABLES TO att_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE att IN SCHEMA public GRANT SELECT ON SEQUENCES TO att_backup;
SQL
systemctl reload postgresql

for ip in ${APP_IPS}; do
  ufw allow from "${ip}" to any port 5432 proto tcp comment 'PostgreSQL from app'
  ufw allow from "${ip}" to any port 6379 proto tcp comment 'Redis from app'
done
ufw allow from "${MON_IP}" to any port 5432 proto tcp comment 'pg_dump backup from mon'
ufw --force enable

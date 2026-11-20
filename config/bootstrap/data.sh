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

for ip in ${APP_IPS}; do
  ufw allow from "${ip}" to any port 5432 proto tcp comment 'PostgreSQL from app'
  ufw allow from "${ip}" to any port 6379 proto tcp comment 'Redis from app'
done
ufw allow from "${MON_IP}" to any port 5432 proto tcp comment 'pg_dump backup from mon'
ufw --force enable

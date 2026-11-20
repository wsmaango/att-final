#!/usr/bin/env bash
# app: Flask API + gunicorn(systemd). 5000 은 lb·mon 에서만 (W7 A4 표: 백엔드는 내부 전용)
set -euxo pipefail
source /etc/att/bootstrap.env

apt-get install -y python3-venv
id att >/dev/null 2>&1 || useradd --system --home /opt/att --shell /usr/sbin/nologin att

install -d -o att -g att /opt/att
cp /opt/bootstrap/app/app.py /opt/bootstrap/app/requirements.txt /opt/att/
python3 -m venv /opt/att/venv
/opt/att/venv/bin/pip install --no-cache-dir -r /opt/att/requirements.txt
chown -R att:att /opt/att

# 시크릿 파일: root 가 쓰고 att 만 읽는다
install -d -m 750 -o root -g att /etc/att
cat > /etc/att/app.env <<ENV
NODE_NAME=${NODE}
BIND_ADDR=${SELF_IP}
DB_HOST=${DATA_IP}
DB_NAME=att
DB_USER=att
DB_PASSWORD=${DB_PASSWORD}
REDIS_HOST=${DATA_IP}
REDIS_PASSWORD=${REDIS_PASSWORD}
CACHE_TTL=10
SPOOL_DIR=/var/lib/att
DEMO_EMPLOYEES=20000
ENV
chown root:att /etc/att/app.env
chmod 640 /etc/att/app.env

# data01 이 먼저 준비돼야 스키마를 만들 수 있다 (최대 10분 대기)
for i in $(seq 1 120); do
  timeout 2 bash -c "</dev/tcp/${DATA_IP}/5432" && break
  [ "$i" -eq 120 ] && { echo "DB 포트가 10분 안에 열리지 않음" >&2; exit 1; }
  sleep 5
done

cp /opt/bootstrap/app/att-app.service /etc/systemd/system/att-app.service
systemctl daemon-reload
systemctl enable --now att-app

for ip in ${LB_IPS}; do
  ufw allow from "${ip}" to any port 5000 proto tcp comment 'API from lb'
done
ufw allow from "${MON_IP}" to any port 5000 proto tcp comment '/metrics from mon'
ufw --force enable

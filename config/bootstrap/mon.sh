#!/usr/bin/env bash
# mon: Prometheus + Grafana(W6) + 원격 백업(pg_dump, RPO 15분 목표)
set -euxo pipefail
source /etc/att/bootstrap.env

apt-get install -y prometheus postgresql-client apt-transport-https gnupg

# --- Prometheus ---
targets() { local port=$1; shift; local out=""; for ip in "$@"; do out+="'${ip}:${port}',"; done; echo "[${out%,}]"; }
cat > /etc/prometheus/prometheus.yml <<CONF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
rule_files:
  - /etc/prometheus/rules/*.yml
scrape_configs:
  - job_name: prometheus
    static_configs: [{ targets: ['localhost:9090'] }]
  - job_name: node
    static_configs: [{ targets: $(targets 9100 ${ALL_IPS}) }]
  - job_name: nginx
    static_configs: [{ targets: $(targets 9113 ${LB_IPS}) }]
  - job_name: app
    static_configs: [{ targets: $(targets 5000 ${APP_IPS}) }]
CONF
install -d /etc/prometheus/rules
cp /opt/bootstrap/alerts.yml /etc/prometheus/rules/att.yml
promtool check config /etc/prometheus/prometheus.yml
systemctl enable prometheus
systemctl restart prometheus

# --- Grafana (apt.grafana.com) ---
install -d -m 755 /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt-get update && apt-get install -y grafana
cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'CONF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    url: http://localhost:9090
    isDefault: true
CONF
# 대시보드도 코드로 (재생성해도 자동 복원)
install -d /var/lib/grafana/dashboards
cp /opt/bootstrap/grafana/att-overview.json /var/lib/grafana/dashboards/
chown -R grafana:grafana /var/lib/grafana/dashboards
cat > /etc/grafana/provisioning/dashboards/att.yml <<'CONF'
apiVersion: 1
providers:
  - name: att
    folder: ATT
    type: file
    options:
      path: /var/lib/grafana/dashboards
CONF
systemctl enable --now grafana-server
systemctl restart grafana-server

# --- 백업: 15분마다 pg_dump (RPO 15분), 7일 보관 ---
id backup-att >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin backup-att
install -d -o backup-att -g backup-att -m 700 /var/backups/att
echo "${DATA_IP}:5432:*:att:${DB_PASSWORD}" > /home/backup-att/.pgpass
chown backup-att:backup-att /home/backup-att/.pgpass && chmod 600 /home/backup-att/.pgpass
cat > /usr/local/bin/att-backup.sh <<CONF
#!/usr/bin/env bash
set -euo pipefail
ts=\$(date +%Y%m%dT%H%M%S)
pg_dump -h ${DATA_IP} -U att -Fc att > /var/backups/att/att-\$ts.dump
find /var/backups/att -name 'att-*.dump' -mtime +7 -delete
echo "att_backup_last_success_timestamp \$(date +%s)" > /var/lib/prometheus/node-exporter/att_backup.prom.tmp
mv /var/lib/prometheus/node-exporter/att_backup.prom.tmp /var/lib/prometheus/node-exporter/att_backup.prom
CONF
chmod 755 /usr/local/bin/att-backup.sh
install -d -m 775 -g backup-att /var/lib/prometheus/node-exporter  # textfile collector
echo "*/15 * * * * backup-att /usr/local/bin/att-backup.sh" > /etc/cron.d/att-backup

ufw allow 3000/tcp comment 'Grafana (perimeter: VPN only)'
ufw allow 9090/tcp comment 'Prometheus UI (perimeter: VPN only)'
ufw --force enable

#!/usr/bin/env bash
# lb: Nginx 리버스 프록시·로드밸런서(W4) + TLS 종료(W7 Part C) + 고객사별 요청 제한 + stub_status(W6)
# 주의: API 응답은 고객사마다 다르므로 Nginx 공유 캐시(W5 proxy_cache)를 쓰지 않는다 (고객사 간 데이터 노출 위험).
#       캐시는 앱에서 tenant_id 를 키에 넣어 Redis 로만 한다.
set -euxo pipefail
source /etc/att/bootstrap.env

apt-get install -y nginx prometheus-nginx-exporter

# self-signed 인증서 (과제 환경. 상용화 시 공인 인증서로 교체 - 리포트 ⑦)
install -d -m 700 /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/lb.key ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/nginx/ssl/lb.key -out /etc/nginx/ssl/lb.crt \
    -subj "/CN=att.local"
  chmod 600 /etc/nginx/ssl/lb.key
fi

UPSTREAMS=""
for ip in ${APP_IPS}; do
  UPSTREAMS+="    server ${ip}:5000 max_fails=2 fail_timeout=5s;"$'\n'
done

cat > /etc/nginx/conf.d/att.conf <<CONF
# 고객사(API 키)별 요청 제한: 한 고객사의 폭주가 다른 고객사를 막지 않도록 (noisy neighbor)
map \$http_x_api_key \$tenant_key { default \$http_x_api_key; "" \$binary_remote_addr; }
limit_req_zone \$tenant_key zone=per_tenant:10m rate=100r/s;
limit_req_status 429;

log_format att '\$remote_addr [\$time_iso8601] "\$request" \$status \$body_bytes_sent '
               'rt=\$request_time urt=\$upstream_response_time ua="\$upstream_addr"';

upstream app_backend {
    least_conn;
${UPSTREAMS}    keepalive 32;
}

server {
    listen 80 default_server;
    server_name _;
    location = /lb-health { access_log off; return 200 "ok\n"; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/lb.crt;
    ssl_certificate_key /etc/nginx/ssl/lb.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    access_log /var/log/nginx/att_access.log att;
    add_header X-LB-Node ${NODE} always;

    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 2s;
    proxy_read_timeout 10s;
    proxy_next_upstream error timeout http_502 http_503 non_idempotent;  # POST 재시도 허용: 앱이 Idempotency-Key 로 중복 방지

    # 출근 체크(쓰기): 9시 직전 몰림. 고객사당 100r/s, 순간 200 까지 대기열로 흡수
    location /api/ {
        limit_req zone=per_tenant burst=200;
        proxy_pass http://app_backend;
    }

    location / {
        proxy_pass http://app_backend;
    }
}

# 관측용 (W6 A6) - 로컬에서만
server {
    listen 127.0.0.1:8080;
    location = /nginx_status { stub_status; }
}
CONF

rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl reload-or-restart nginx

# nginx exporter → :9113
echo 'ARGS="-nginx.scrape-uri=http://127.0.0.1:8080/nginx_status"' > /etc/default/prometheus-nginx-exporter
systemctl enable --now prometheus-nginx-exporter
systemctl restart prometheus-nginx-exporter

ufw allow 80/tcp  comment 'HTTP redirect'
ufw allow 443/tcp comment 'HTTPS service'
ufw allow from "${MON_IP}" to any port 9113 proto tcp comment 'nginx exporter from mon'
ufw --force enable

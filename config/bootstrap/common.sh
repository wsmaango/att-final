#!/usr/bin/env bash
# 모든 VM 공통: 패키지, node_exporter(W6), SSH 하드닝(W7 Part B), ufw 기본값(W7 Part A)
set -euxo pipefail
source /etc/att/bootstrap.env

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y prometheus-node-exporter ufw curl jq chrony

# --- SSH 하드닝: 키 인증만, root 로그인 금지 ---
cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
MaxAuthTries 3
CONF
sshd -t && systemctl reload ssh

# --- ufw: 기본 차단, 필요한 것만 (역할 스크립트가 추가) ---
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH admin (perimeter: VR firewall VPN only)'
ufw allow from "${MON_IP}" to any port 9100 proto tcp comment 'node_exporter from mon'
ufw logging low

systemctl enable --now prometheus-node-exporter

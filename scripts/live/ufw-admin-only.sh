#!/usr/bin/env bash
# 실행 중인 서버에 7단계 접근 제어 개선을 적용한다 (root). 첫 줄로 ADMIN_CIDRS="a/32 b/24" 를 받는다.
#  - SSH(22)를 Anywhere → admin_cidrs 로 좁힘 (common.sh 와 같은 규칙)
#  - mon01 이면 Grafana(3000)·Prometheus(9090)도 admin_cidrs 로 좁힘 (mon.sh 와 같은 규칙)
#  - X11Forwarding no
# 안전장치: 규칙을 바꾸기 전 상태를 저장하고 3분 뒤 자동으로 되돌리는 타이머를 건다.
#          새 SSH 접속이 되는 것을 확인한 뒤 'systemctl stop ufw-rollback.timer' 로 취소한다.
set -euo pipefail
: "${ADMIN_CIDRS:?}"

cp /etc/ufw/user.rules /root/ufw-user.rules.bak
cp /etc/ufw/user6.rules /root/ufw-user6.rules.bak
systemctl stop ufw-rollback.timer 2>/dev/null || true
systemd-run --quiet --unit=ufw-rollback --on-active=180 \
  bash -c 'cp /root/ufw-user.rules.bak /etc/ufw/user.rules; cp /root/ufw-user6.rules.bak /etc/ufw/user6.rules; ufw reload'
echo "rollback timer: 3분 뒤 자동 복구 (취소: systemctl stop ufw-rollback.timer)"

has() { ufw status | grep -Eq "^$1/tcp +ALLOW( IN)? +Anywhere"; }  # status 는 "ALLOW", status numbered·verbose 는 "ALLOW IN"
narrow() {  # $1=port $2=설명
  for c in $ADMIN_CIDRS; do ufw allow from "$c" to any port "$1" proto tcp comment "$2 admin_cidrs only" >/dev/null; done
  # Anywhere 규칙(v4·v6)을 번호로 지운다. 지울 때마다 번호가 바뀌므로 하나씩 다시 찾는다.
  while n=$(ufw status numbered | grep -E "^\[ *[0-9]+\] $1/tcp( \(v6\))? +ALLOW( IN)? +Anywhere" | head -1 | sed -E 's/^\[ *([0-9]+)\].*/\1/'); [ -n "$n" ]; do
    ufw --force delete "$n" >/dev/null
  done
}
narrow 22 SSH
has 3000 && narrow 3000 Grafana
has 9090 && narrow 9090 "Prometheus UI"

f=/etc/ssh/sshd_config.d/10-hardening.conf
grep -q '^X11Forwarding' "$f" || echo 'X11Forwarding no' >> "$f"
sshd -t && systemctl reload ssh

echo "--- $(hostname)"
ufw status | sed -n '/^To/,$p'
sshd -T | grep -E '^x11forwarding '

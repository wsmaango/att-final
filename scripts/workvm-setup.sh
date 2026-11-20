#!/usr/bin/env bash
# Solid Cloud 작업 VM(Ubuntu 22.04/24.04)에 과제 도구를 한 번에 설치한다. 아웃바운드 80/443 이 열려 있어야 한다.
# 사용: bash scripts/workvm-setup.sh
set -euo pipefail
sudo apt-get update
sudo apt-get install -y git jq curl unzip gnupg lsb-release tmux pipx perl zip netcat-openbsd postgresql-client

# Terraform (HashiCorp 공식 apt 저장소)
if ! command -v terraform >/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update && sudo apt-get install -y terraform
fi

# k6 (Grafana 공식 apt 저장소)
if ! command -v k6 >/dev/null; then
  curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
  sudo apt-get update && sudo apt-get install -y k6
fi

# Checkov (pipx: Ubuntu 시스템 파이썬을 건드리지 않음)
pipx ensurepath >/dev/null
command -v checkov >/dev/null || pipx install checkov

# tflint (공식 설치 스크립트)
command -v tflint >/dev/null || curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# gitleaks (GitHub 최신 릴리스)
if ! command -v gitleaks >/dev/null; then
  url=$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
        | jq -r '.assets[].browser_download_url' | grep 'linux_x64.tar.gz$' | head -1)
  curl -fsSL "$url" | sudo tar -xz -C /usr/local/bin gitleaks
fi

echo "== 설치 확인 (새 셸에서 checkov 가 안 보이면 'source ~/.bashrc')"
for c in terraform git k6 tflint gitleaks jq tmux; do printf '%-10s ' "$c"; command -v "$c" >/dev/null && echo ok || echo MISSING; done
~/.local/bin/checkov --version >/dev/null 2>&1 && echo "checkov    ok" || echo "checkov    MISSING (source ~/.bashrc 후 확인)"

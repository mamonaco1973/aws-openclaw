#!/bin/bash
set -euo pipefail

# Centralized user-data logging
LOG=/root/userdata.log
mkdir -p /root
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR

echo "user-data start: $(date -Is)"

apt-get update -y
apt-get install -y curl unzip python3-pip python3-venv

# Install SSM agent — Ubuntu 24.04 ships it via snap; use snap if already
# present to avoid dpkg conflict, otherwise install via snap.
if snap list amazon-ssm-agent &>/dev/null; then
  snap start amazon-ssm-agent
else
  snap install amazon-ssm-agent --classic
fi
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Install and configure pnpm
npm install -g pnpm
export PNPM_HOME="/root/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
export SHELL=/bin/bash
pnpm setup

# Install OpenClaw
pnpm add -g openclaw@latest
printf 'a\n' | pnpm approve-builds -g

# Install LiteLLM proxy in a virtualenv
python3 -m venv /opt/litellm-venv
/opt/litellm-venv/bin/pip install 'litellm[proxy]'

# LiteLLM config pointing at Bedrock
mkdir -p /etc/litellm
cat > /etc/litellm/config.yaml <<'LITELLM'
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/anthropic.claude-sonnet-4-5
      aws_region_name: us-east-1

general_settings:
  master_key: "sk-openclaw"
LITELLM

# LiteLLM systemd service
cat > /etc/systemd/system/litellm.service <<'SERVICE'
[Unit]
Description=LiteLLM Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/litellm-venv/bin/litellm --config /etc/litellm/config.yaml --port 4000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable litellm
systemctl start litellm

echo "NOTE: Userdata script completed."
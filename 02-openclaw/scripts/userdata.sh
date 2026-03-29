#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y curl unzip python3-pip python3-venv

# Install SSM agent
curl -fsSL https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb \
  -o /tmp/amazon-ssm-agent.deb
dpkg -i /tmp/amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Install and configure pnpm
npm install -g pnpm
export PNPM_HOME="/root/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
pnpm setup

# Install OpenClaw
pnpm add -g openclaw@latest
yes | pnpm approve-builds -g

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

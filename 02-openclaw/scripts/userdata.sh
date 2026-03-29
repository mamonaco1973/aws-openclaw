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
apt-get install -y curl ca-certificates

# ================================================================================
# SSM Agent
# ================================================================================

# Ubuntu 24.04 ships SSM agent via snap; use snap if already present to avoid
# dpkg conflict, otherwise install via snap.
if snap list amazon-ssm-agent &>/dev/null; then
  snap start amazon-ssm-agent
else
  snap install amazon-ssm-agent --classic
fi
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# ================================================================================
# Docker
# ================================================================================

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# ================================================================================
# Config Files
# ================================================================================

mkdir -p /opt/openclaw
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace

# LiteLLM config — bedrock_model_id injected by Terraform templatefile()
cat > /opt/openclaw/litellm-config.yaml <<LITELLM
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/${bedrock_model_id}
      aws_region_name: us-east-1
  - model_name: claude-opus-4-6
    litellm_params:
      model: bedrock/${bedrock_model_id}
      aws_region_name: us-east-1

general_settings:
  master_key: "sk-openclaw"
LITELLM

# OpenClaw config — pre-configures the LiteLLM provider so onboarding is not
# required after deployment.
cat > /opt/openclaw/config/openclaw.json <<'OPENCLAW'
{
  "models": {
    "mode": "merge",
    "providers": {
      "litellm": {
        "baseUrl": "http://litellm:4000",
        "apiKey": "sk-openclaw",
        "api": "openai-completions",
        "models": [
          { "id": "claude-sonnet",  "name": "Claude Sonnet (Bedrock)" },
          { "id": "claude-opus-4-6", "name": "Claude Opus 4.6 (Bedrock)" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "litellm/claude-sonnet" }
    }
  }
}
OPENCLAW

# Docker Compose stack
cat > /opt/openclaw/docker-compose.yml <<'COMPOSE'
services:

  litellm:
    image: docker.litellm.ai/berriai/litellm:main-stable
    container_name: litellm
    volumes:
      - /opt/openclaw/litellm-config.yaml:/app/config.yaml
    restart: unless-stopped
    command: ["--config", "/app/config.yaml", "--port", "4000"]

  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    depends_on:
      - litellm
    volumes:
      - /opt/openclaw/config:/home/node/.openclaw
      - /opt/openclaw/workspace:/home/node/.openclaw/workspace
    ports:
      - "18789:18789"
    init: true
    restart: unless-stopped
    command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]

COMPOSE

# ================================================================================
# Start Stack
# ================================================================================

cd /opt/openclaw
docker compose pull
docker compose up -d

echo "NOTE: Userdata script completed."
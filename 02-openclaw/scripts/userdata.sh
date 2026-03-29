#!/bin/bash
set -euo pipefail

# Centralized user-data logging
LOG=/root/userdata.log
mkdir -p /root
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR

echo "NOTE: user-data start: $(date -Is)"

echo "NOTE: [base-packages] installing curl and ca-certificates"
apt-get update -y
apt-get install -y curl ca-certificates
echo "NOTE: [base-packages] done"

# ================================================================================
# SSM Agent
# ================================================================================

echo "NOTE: [ssm-agent] starting install"

# Ubuntu 24.04 ships SSM agent via snap; use snap if already present to avoid
# dpkg conflict, otherwise install via snap.
if snap list amazon-ssm-agent &>/dev/null; then
  echo "NOTE: [ssm-agent] already installed via snap, starting"
  snap start amazon-ssm-agent
else
  echo "NOTE: [ssm-agent] not found, installing via snap"
  snap install amazon-ssm-agent --classic
fi
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
echo "NOTE: [ssm-agent] done"

# ================================================================================
# Docker
# ================================================================================

echo "NOTE: [docker] adding apt repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
echo "NOTE: [docker] apt repository added"

echo "NOTE: [docker] installing packages"
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
echo "NOTE: [docker] packages installed"

echo "NOTE: [docker] enabling and starting service"
systemctl enable docker
systemctl start docker
echo "NOTE: [docker] service running"

# ================================================================================
# Config Files
# ================================================================================

echo "NOTE: [config] creating directories"
mkdir -p /opt/openclaw
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace
# openclaw container runs as node (UID 1000) — config and workspace must be writable
chown -R 1000:1000 /opt/openclaw/config /opt/openclaw/workspace
echo "NOTE: [config] directories created"

echo "NOTE: [config] writing litellm-config.yaml (model: ${bedrock_model_id})"
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
echo "NOTE: [config] litellm-config.yaml written"

echo "NOTE: [config] writing openclaw.json"
cat > /opt/openclaw/config/openclaw.json <<'OPENCLAW'
{
  "gateway": {
    "mode": "local"
  },
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
echo "NOTE: [config] openclaw.json written"

echo "NOTE: [config] writing docker-compose.yml"
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
echo "NOTE: [config] docker-compose.yml written"

# ================================================================================
# Start Stack
# ================================================================================

echo "NOTE: [compose] pulling images"
cd /opt/openclaw
docker compose pull
echo "NOTE: [compose] images pulled"

echo "NOTE: [compose] starting stack"
docker compose up -d
echo "NOTE: [compose] stack started"

echo "NOTE: Userdata script completed."
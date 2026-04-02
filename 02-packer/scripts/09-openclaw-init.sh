#!/bin/bash
set -euo pipefail

# ================================================================================
# OpenClaw Config Initialization
# ================================================================================
#
# Runs the openclaw gateway briefly as the openclaw user to stamp the config
# file with internal metadata. Without this step, openclaw detects a
# "missing-meta-before-write" condition on first launch and overwrites any
# pre-written config with defaults, discarding the litellm provider settings.
#
# Flow:
#   1. Start litellm with a placeholder config so models auth can connect.
#   2. Run openclaw gateway in background as openclaw user (stamps config).
#   3. Configure the litellm model provider via CLI.
#   4. Stop both processes — config is persisted at /home/openclaw/.openclaw.
#
# ================================================================================

echo "NOTE: [openclaw-init] writing placeholder litellm config"
mkdir -p /opt/openclaw
cat > /opt/openclaw/litellm-config.yaml <<'LITELLM'
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-east-1

  - model_name: nova-pro
    litellm_params:
      model: bedrock/us.amazon.nova-pro-v1:0
      aws_region_name: us-east-1

  - model_name: llama
    litellm_params:
      model: bedrock/us.meta.llama3-3-70b-instruct-v1:0
      aws_region_name: us-east-1

general_settings:
  master_key: "sk-openclaw"
LITELLM
chown openclaw:openclaw /opt/openclaw/litellm-config.yaml

echo "NOTE: [openclaw-init] starting litellm placeholder"
sudo -u openclaw /opt/litellm-venv/bin/litellm \
  --config /opt/openclaw/litellm-config.yaml --port 4000 &
LITELLM_PID=$!
sleep 8

OPENCLAW_BIN=$(which openclaw)
echo "NOTE: [openclaw-init] openclaw binary: ${OPENCLAW_BIN}"

echo "NOTE: [openclaw-init] starting openclaw gateway to stamp config metadata"
sudo -u openclaw env HOME=/home/openclaw PATH="${PATH}" bash -c "
  ${OPENCLAW_BIN} gateway run \
    --allow-unconfigured --bind loopback --port 18789 &
  echo \$! > /tmp/openclaw-init.pid
"
sleep 12

echo "NOTE: [openclaw-init] configuring litellm model provider"
sudo -u openclaw env HOME=/home/openclaw PATH="${PATH}" bash -c "
  ${OPENCLAW_BIN} config set gateway.mode local || true
  ${OPENCLAW_BIN} config set models.providers.litellm \
    '{\"baseUrl\":\"http://localhost:4000\",\"apiKey\":\"sk-openclaw\",\"models\":[{\"id\":\"claude-sonnet\",\"name\":\"Claude Sonnet (Bedrock)\"},{\"id\":\"nova-pro\",\"name\":\"Amazon Nova Pro (Bedrock)\"},{\"id\":\"llama\",\"name\":\"Meta Llama 3 70B (Bedrock)\"}]}' \
    --strict-json || true
  ${OPENCLAW_BIN} models set litellm/claude-sonnet || true
"

echo "NOTE: [openclaw-init] stopping all openclaw and litellm processes"
# Kill all processes running as the openclaw user — this catches the gateway,
# any restarted child processes, node workers, and uvicorn/litellm children
# that pkill -f misses.
pkill -u openclaw 2>/dev/null || true
sleep 3
# Force-kill anything still alive
pkill -9 -u openclaw 2>/dev/null || true
rm -f /tmp/openclaw-init.pid

echo "NOTE: [openclaw-init] config directory contents:"
ls -la /home/openclaw/.openclaw/ 2>/dev/null || echo "(empty)"

echo "NOTE: [openclaw-init] done"

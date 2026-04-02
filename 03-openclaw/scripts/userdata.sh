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


# ================================================================================
# Credentials
# ================================================================================

echo "NOTE: [credentials] reading openclaw credentials from Secrets Manager"
secret=$(aws secretsmanager get-secret-value \
  --secret-id openclaw_credentials \
  --query SecretString \
  --output text)

OPENCLAW_PASSWORD=$(echo "$secret" | jq -r '.password')

echo "NOTE: [credentials] setting openclaw user password"
echo "openclaw:$${OPENCLAW_PASSWORD}" | chpasswd
echo "NOTE: [credentials] done"


# ================================================================================
# LiteLLM Config
# ================================================================================

echo "NOTE: [litellm] writing config"
cat > /opt/openclaw/litellm-config.yaml <<LITELLM
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/${bedrock_model_id}
      aws_region_name: us-east-1

  - model_name: claude-haiku
    litellm_params:
      model: bedrock/${haiku_model_id}
      aws_region_name: us-east-1

  - model_name: nova-pro
    litellm_params:
      model: bedrock/${nova_pro_model_id}
      aws_region_name: us-east-1

  - model_name: nova-lite
    litellm_params:
      model: bedrock/${nova_lite_model_id}
      aws_region_name: us-east-1

general_settings:
  master_key: "sk-openclaw"
  drop_params: true
LITELLM
chown openclaw:openclaw /opt/openclaw/litellm-config.yaml
echo "NOTE: [litellm] config written"


# ================================================================================
# Start Services
# ================================================================================

echo "NOTE: [services] starting litellm"
systemctl start litellm

echo "NOTE: [services] starting openclaw-gateway"
systemctl start openclaw-gateway

echo "NOTE: [services] done"

echo "NOTE: user-data complete: $(date -Is)"

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
# One entry per model in bedrock-config.sh. The alias is what OpenClaw asks
# for; the Bedrock id behind it can change without repointing any agent.
model_list:
%{ for m in models ~}
  - model_name: ${m.alias}
    litellm_params:
      model: bedrock/${m.model}
      aws_region_name: ${bedrock_region}
%{ endfor ~}

# drop_params belongs here, NOT only in general_settings, where LiteLLM never
# reads it. OpenClaw sends OpenAI parameters some Bedrock models reject
# outright; without this a request carrying an unsupported field fails instead
# of being trimmed.
litellm_settings:
  drop_params: true

general_settings:
  master_key: "sk-openclaw"
  drop_params: true
LITELLM
chown openclaw:openclaw /opt/openclaw/litellm-config.yaml
echo "NOTE: [litellm] config written for these models:"
grep '^  - model_name:' /opt/openclaw/litellm-config.yaml


# ================================================================================
# Start Services
# ================================================================================

echo "NOTE: [ses] reading SMTP credentials from Secrets Manager"
ses_secret=$(aws secretsmanager get-secret-value \
  --secret-id openclaw_ses_smtp \
  --query SecretString \
  --output text 2>/dev/null || echo "{}")

SMTP_HOST=$(echo "$ses_secret" | jq -r '.smtp_host // empty')
SMTP_PORT=$(echo "$ses_secret" | jq -r '.smtp_port // empty')
SMTP_USERNAME=$(echo "$ses_secret" | jq -r '.smtp_username // empty')
SMTP_PASSWORD=$(echo "$ses_secret" | jq -r '.smtp_password // empty')
SMTP_FROM=$(echo "$ses_secret" | jq -r '.from_email // empty')

if [ -n "$SMTP_HOST" ]; then
  echo "NOTE: [ses] injecting SMTP credentials into gateway service"
  mkdir -p /etc/systemd/system/openclaw-gateway.service.d
  cat > /etc/systemd/system/openclaw-gateway.service.d/ses.conf <<EOF
[Service]
Environment="SMTP_HOST=$${SMTP_HOST}"
Environment="SMTP_PORT=$${SMTP_PORT}"
Environment="SMTP_USERNAME=$${SMTP_USERNAME}"
Environment="SMTP_PASSWORD=$${SMTP_PASSWORD}"
Environment="SMTP_FROM=$${SMTP_FROM}"
EOF
  systemctl daemon-reload

  echo "NOTE: [ses] configuring msmtp for system-wide email sending"
  cat > /etc/msmtprc <<EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        ses
host           $${SMTP_HOST}
port           $${SMTP_PORT}
from           $${SMTP_FROM}
user           $${SMTP_USERNAME}
password       $${SMTP_PASSWORD}

account default : ses
EOF
  chmod 600 /etc/msmtprc
  touch /var/log/msmtp.log
  chmod 666 /var/log/msmtp.log

  cp /etc/msmtprc /home/openclaw/.msmtprc
  chown openclaw:openclaw /home/openclaw/.msmtprc
  chmod 600 /home/openclaw/.msmtprc

  echo "NOTE: [ses] writing email capability note to agent workspace"
  mkdir -p /home/openclaw/.openclaw/agents/main/workspace
  cat > /home/openclaw/.openclaw/agents/main/workspace/EMAIL.md <<EOF
# Email Sending

msmtp is configured system-wide with AWS SES SMTP credentials.
Use the \`mail\` command via exec to send email — no additional setup needed.

## Send a plain text email
\`\`\`bash
echo "Message body here" | mail -s "Subject" recipient@example.com
\`\`\`

## Send with a file attachment
\`\`\`bash
mail -s "Subject" -A /path/to/file.docx recipient@example.com < /dev/null
\`\`\`

## Send with body and attachment
\`\`\`bash
echo "Please find the report attached." | mail -s "Report" -A /path/to/report.docx recipient@example.com
\`\`\`

From address: $${SMTP_FROM}
EOF
  # chown the whole tree, NOT just workspace/. This script runs as root, so
  # the mkdir -p above creates agents/ and agents/main/ root-owned too; a
  # chown that starts at workspace/ never reaches them, and the gateway
  # (running as openclaw) then fails with EACCES creating anything else
  # under agents/main -- e.g. the main agent's session storage.
  chown -R openclaw:openclaw /home/openclaw/.openclaw

  # The image's HEARTBEAT.md and SYSTEM.md say nothing about email, because
  # SES is optional (ses_email in 01-core). Tell the agent only now that the
  # credentials are known to exist.
  echo "NOTE: [ses] adding email to the agent's workspace notes"
  WORKSPACE=/home/openclaw/.openclaw/workspace
  mkdir -p "$${WORKSPACE}"
  cat >> "$${WORKSPACE}/HEARTBEAT.md" <<'NOTE'
- **Email**: Send email via the `mail` command (msmtp + AWS SES SMTP): `echo "body" | mail -s "Subject" recipient@example.com`
NOTE
  cat >> "$${WORKSPACE}/SYSTEM.md" <<NOTE

## Email
msmtp is configured system-wide with AWS SES SMTP credentials. Use the
\`mail\` command -- the from address ($${SMTP_FROM}) is pre-configured.

\`\`\`bash
# Plain text
echo "Body here" | mail -s "Subject" recipient@example.com

# With attachment
echo "See attached." | mail -s "Subject" -A /path/to/file.docx recipient@example.com
\`\`\`

SES only delivers once $${SMTP_FROM} has been verified, and while the account
is in the SES sandbox the recipient must be verified too.
NOTE
  chown -R openclaw:openclaw "$${WORKSPACE}"

  echo "NOTE: [ses] done"
else
  echo "NOTE: [ses] no SES secret found, skipping"
fi


echo "NOTE: [services] starting litellm"
systemctl start litellm

echo "NOTE: [services] starting openclaw-gateway"
systemctl start openclaw-gateway


# ================================================================================
# OpenClaw Model Registration
# ================================================================================
#
# The AMI bakes in the four models 09-openclaw-init.sh knew about. Replace that
# with the list from bedrock-config.sh, so the picker offers exactly what
# LiteLLM serves -- an alias the picker shows but LiteLLM lacks fails only when
# someone selects it.

echo "NOTE: [openclaw] registering models from bedrock-config.sh"

# Wait for the gateway to finish stamping its config
sleep 20

OPENCLAW_BIN=$(which openclaw)

# Decoded from base64 rather than interpolated as JSON: a display name
# containing an apostrophe would otherwise break out of the quoted string.
MODELS_JSON=$(echo '${models_b64}' | base64 -d | jq -c '.')
PRIMARY_ALIAS='${primary_alias}'

PROVIDER_JSON=$(jq -n --argjson models "$${MODELS_JSON}" '{
  baseUrl: "http://localhost:4000",
  apiKey:  "sk-openclaw",
  models:  $models
}')

# "$@" is deliberate and must NOT be written "$$@". templatefile only treats
# $$ as an escape when a { follows it, so $$@ survives into the rendered
# script and bash reads it as $$ (the PID) plus a literal @.
run_openclaw() {
  sudo -u openclaw env HOME=/home/openclaw PATH="$${PATH}" \
    "$${OPENCLAW_BIN}" "$@"
}

if ! run_openclaw config set models.providers.litellm \
     "$${PROVIDER_JSON}" --strict-json; then
  echo "ERROR: [openclaw] failed to register the litellm provider - the"
  echo "ERROR: [openclaw] model picker will show whatever was baked in."
fi

run_openclaw config set agents.defaults.model.primary \
  "litellm/$${PRIMARY_ALIAS}"

echo "NOTE: [openclaw] restarting gateway to apply model config"
systemctl restart openclaw-gateway

echo "NOTE: [services] done"

echo "NOTE: user-data complete: $(date -Is)"

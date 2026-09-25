#!/bin/bash
# ================================================================================
# validate.sh
# ================================================================================
#
# Purpose:
#   Post-deploy validation for the OpenClaw AI Agent Workstation on AWS.
#   Reads Terraform outputs and prints connection details.
#
# ================================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/03-openclaw"

cd "${TF_DIR}"

INSTANCE_ID="$(terraform output -raw instance_id  2>/dev/null || echo '<not found>')"
PUBLIC_IP="$(terraform output -raw public_ip       2>/dev/null || echo '<not found>')"
PUBLIC_DNS="$(terraform output -raw public_dns     2>/dev/null || echo '<not found>')"
SECRET_ID="$(terraform output -raw credentials_secret_id 2>/dev/null || echo 'openclaw_credentials')"

# With no state, terraform output prints nothing and still exits 0, so the
# fallbacks above never fire. Apply them to empty values too.
INSTANCE_ID="${INSTANCE_ID:-<not found>}"
PUBLIC_IP="${PUBLIC_IP:-<not found>}"
PUBLIC_DNS="${PUBLIC_DNS:-<not found>}"
SECRET_ID="${SECRET_ID:-openclaw_credentials}"

# Print the password outright rather than sending the operator off to look
# it up. Secrets Manager stays the source of truth; this just reads it back.
CREDS_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_ID}" \
  --query SecretString \
  --output text 2>/dev/null || true)"
if [ -n "${CREDS_JSON}" ]; then
  PASSWORD="$(printf '%s' "${CREDS_JSON}" | jq -r '.password')"
else
  # Usually means the caller lacks secretsmanager:GetSecretValue, or the
  # deploy has not finished. Fall back to showing the lookup command.
  PASSWORD="<unavailable> - run: aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text | jq -r .password"
fi

echo ""
echo "================================================="
echo "OpenClaw AI Agent Workstation - Quick Start (AWS)"
echo "================================================="
echo ""

printf "%-28s %s\n" "NOTE: Instance ID:"          "${INSTANCE_ID}"
printf "%-28s %s\n" "NOTE: Public IP:"             "${PUBLIC_IP}"
printf "%-28s %s\n" "NOTE: Public FQDN:"           "${PUBLIC_DNS}"
echo ""
printf "%-28s %s\n" "NOTE: RDP Host:"              "${PUBLIC_IP}:3389"
printf "%-28s %s\n" "NOTE: Username:"              "openclaw"
printf "%-28s %s\n" "NOTE: Password:"              "${PASSWORD}"
echo ""

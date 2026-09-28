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

# One terraform invocation, not four. Each `terraform output` reloads the
# backend and the provider plugins before printing a single string, so reading
# four values separately cost four full Terraform startups.
OUTPUTS="$(terraform output -json 2>/dev/null || echo '{}')"

# With no state, terraform output prints an empty object and still exits 0, so
# the jq defaults below double as the not-deployed case.
INSTANCE_ID="$(jq -r '.instance_id.value // "<not found>"'             <<<"${OUTPUTS}")"
PUBLIC_IP="$(jq   -r '.public_ip.value // "<not found>"'               <<<"${OUTPUTS}")"
PUBLIC_DNS="$(jq  -r '.public_dns.value // "<not found>"'              <<<"${OUTPUTS}")"
SECRET_ID="$(jq   -r '.credentials_secret_id.value // "openclaw_credentials"' <<<"${OUTPUTS}")"

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

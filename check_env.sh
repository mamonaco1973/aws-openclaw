#!/bin/bash
# ==============================================================================
# check_env.sh - Environment Validation
# ------------------------------------------------------------------------------
# Purpose:
#   - Validates that required CLI tools are available in the current PATH.
#   - Verifies AWS CLI authentication and connectivity.
#
# Scope:
#   - Checks for aws, terraform, jq, packer and python3 binaries.
#   - Confirms the caller identity via AWS STS.
#   - Verifies every model in bedrock-config.sh actually answers on Bedrock.
#
# Fast-Fail Behavior:
#   - Script exits immediately on command failure, unset variables,
#     or failed pipelines.
#
# Requirements:
#   - AWS CLI installed and configured.
#   - Terraform installed.
#   - jq installed.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Required Commands
# ------------------------------------------------------------------------------
echo "NOTE: Validating required commands in PATH."

commands=("aws" "terraform" "jq" "packer" "python3")

for cmd in "${commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${cmd}"
    exit 1
  fi

  echo "NOTE: Found required command: ${cmd}"
done

echo "NOTE: All required commands are available."

# ------------------------------------------------------------------------------
# AWS Connectivity Check
# ------------------------------------------------------------------------------
echo "NOTE: Verifying AWS CLI connectivity..."

aws sts get-caller-identity --query "Account" --output text >/dev/null

echo "NOTE: AWS CLI authentication successful."

# ==============================================================================
# SECTION: Bedrock Model Check
# ==============================================================================
#
# Not merely a lookup: an inference profile can be ACTIVE and still return
# AccessDenied for this account. The only reliable test is to make the call,
# so probe_bedrock.py makes it -- once per model in bedrock-config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bedrock-config.sh"

mapfile -t MODEL_IDS < <(bedrock_model_ids)

if [ "${#MODEL_IDS[@]}" -eq 0 ]; then
  echo "ERROR: BEDROCK_MODELS in bedrock-config.sh is empty - nothing to deploy."
  exit 1
fi

# A primary that is not in the list yields an OpenClaw that starts fine and
# cannot run an agent. Terraform validates this too, but failing here means
# failing before anything is built.
if ! bedrock_model_for_alias "${BEDROCK_PRIMARY}" > /dev/null; then
  echo "ERROR: BEDROCK_PRIMARY is '${BEDROCK_PRIMARY}', which is not an alias in"
  echo "ERROR: BEDROCK_MODELS. Valid aliases:"
  bedrock_model_aliases | sed 's/^/ERROR:   /'
  exit 1
fi

echo "NOTE: Checking ${#MODEL_IDS[@]} model(s) in ${BEDROCK_REGION}," \
     "primary ${BEDROCK_PRIMARY}"

MODEL_FAILED=0
for model in "${MODEL_IDS[@]}"; do
  if result=$(python3 "${SCRIPT_DIR}/probe_bedrock.py" \
       --check "${model}" --region "${BEDROCK_REGION}" 2>&1); then
    echo "NOTE: Bedrock model ${model} accessible."
  else
    echo "ERROR: Bedrock model ${model} did not answer in ${BEDROCK_REGION}."
    echo "ERROR:   ${result}"
    MODEL_FAILED=1
  fi
done

if [ "${MODEL_FAILED}" -ne 0 ]; then
  echo "ERROR: One or more models in bedrock-config.sh are unavailable."
  echo "ERROR: Model access is granted per account and region:"
  echo "ERROR:   https://console.aws.amazon.com/bedrock/home#/modelaccess"
  echo "ERROR: Run ./probe_bedrock.py to see what this account can serve, then"
  echo "ERROR: update BEDROCK_MODELS in bedrock-config.sh."
  exit 1
fi

echo "NOTE: All models in bedrock-config.sh are available."

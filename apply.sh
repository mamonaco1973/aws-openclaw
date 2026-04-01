#!/bin/bash
# ================================================================================
# FILE: apply.sh
# ================================================================================
#
# Purpose:
#   Deploy core infrastructure.
#
# Deployment Flow:
#     1. Deploy core infrastructure (Terraform).
#     2. Build OpenClaw AMI (Packer).
#     3. Deploy OpenClaw EC2 host (Terraform).
#
# Design Principles:
#   - Fail-fast behavior using set -euo pipefail.
#   - Environment validation before execution.
#   - Post-build validation after provisioning completes.
#
# Requirements:
#   - AWS CLI configured with sufficient IAM permissions.
#   - Terraform installed and in PATH.
#   - check_env.sh and validate.sh present in working directory.
#
# Exit Codes:
#   0 = Success
#   1 = Validation failure or provisioning error
#
# ================================================================================


# ================================================================================
# SECTION: Configuration
# ================================================================================

# Target AWS region.
export AWS_DEFAULT_REGION="us-east-1"

# Fail on errors, unset variables, and pipe failures.
set -euo pipefail


# ================================================================================
# SECTION: Environment Validation
# ================================================================================

echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi


# ================================================================================
# PHASE 1: Core Infrastructure
# ================================================================================

echo "NOTE: Building core infrastructure..."

cd 01-core || {
  echo "ERROR: Directory 01-core not found"
  exit 1
}

terraform init
terraform apply -auto-approve

cd ..


# ================================================================================
# PHASE 2: Build OpenClaw AMI (Packer)
# ================================================================================

echo "NOTE: Building OpenClaw AMI with Packer..."

vpc_id=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=clawd-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

subnet_id=$(aws ec2 describe-subnets \
  --filters \
    "Name=vpc-id,Values=${vpc_id}" \
    "Name=tag:Name,Values=pub-subnet-1" \
  --query "Subnets[0].SubnetId" \
  --output text)

cd 02-packer || {
  echo "ERROR: Directory 02-packer not found"
  exit 1
}

packer init ./openclaw.pkr.hcl
packer build \
  -var "vpc_id=${vpc_id}" \
  -var "subnet_id=${subnet_id}" \
  ./openclaw.pkr.hcl

cd ..


# ================================================================================
# SECTION: Bedrock Model Discovery
# ================================================================================

echo "NOTE: Resolving latest active Claude Sonnet foundation model..."

BASE_MODEL_ID=$(aws bedrock list-foundation-models \
  --by-provider anthropic \
  --query 'modelSummaries[?modelLifecycle.status==`ACTIVE` && contains(modelId, `claude-sonnet`)]' \
  --output json | jq -r '[.[] | select(.modelId | test("-v[0-9]+:[0-9]+$"))] | [.[].modelId] | sort | last')

if [ -z "${BASE_MODEL_ID}" ] || [ "${BASE_MODEL_ID}" = "null" ]; then
  echo "ERROR: Could not resolve a Claude Sonnet foundation model from Bedrock."
  exit 1
fi

# Recent Claude models require cross-region inference profiles (us. prefix)
BEDROCK_MODEL_ID="us.${BASE_MODEL_ID}"

echo "NOTE: Using Bedrock model: ${BEDROCK_MODEL_ID}"


# ================================================================================
# PHASE 3: OpenClaw Host
# ================================================================================

echo "NOTE: Building OpenClaw host..."

cd 03-openclaw || {
  echo "ERROR: Directory 03-openclaw not found"
  exit 1
}

terraform init
terraform apply -auto-approve -var="bedrock_model_id=${BEDROCK_MODEL_ID}"

cd ..


# ================================================================================
# SECTION: Post-Deployment Validation
# ================================================================================

./validate.sh

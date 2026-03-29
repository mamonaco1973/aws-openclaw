#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Orchestrate controlled teardown of core infrastructure.
#
# Teardown Order:
#     1. Destroy OpenClaw EC2 host (03-openclaw).
#     2. Deregister openclaw_mate_ami and its EBS snapshot.
#     3. Destroy core infrastructure (01-core).
#
# Design Principles:
#   - Fail-fast behavior for safe teardown.
#
# Requirements:
#   - AWS CLI configured and authenticated.
#   - Terraform installed and initialized per module.
#
# Exit Codes:
#   0 = Success
#   1 = Missing directories or Terraform/AWS CLI error
#
# ================================================================================

set -euo pipefail


# ================================================================================
# SECTION: Configuration
# ================================================================================

export AWS_DEFAULT_REGION="us-east-1"


# ================================================================================
# PHASE 1: Destroy OpenClaw Host
# ================================================================================

echo "NOTE: Destroying OpenClaw host..."

cd 03-openclaw || {
  echo "ERROR: Directory 03-openclaw not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 2: Deregister OpenClaw MATE AMI
# ================================================================================

echo "NOTE: Deregistering openclaw_mate_ami..."

ami_id=$(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=openclaw_mate_ami*" \
  --query "Images[0].ImageId" \
  --output text 2>/dev/null || true)

if [ -n "${ami_id}" ] && [ "${ami_id}" != "None" ]; then
  snapshot_id=$(aws ec2 describe-images \
    --image-ids "${ami_id}" \
    --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" \
    --output text)
  aws ec2 deregister-image --image-id "${ami_id}"
  echo "NOTE: Deregistered AMI ${ami_id}"
  if [ -n "${snapshot_id}" ] && [ "${snapshot_id}" != "None" ]; then
    aws ec2 delete-snapshot --snapshot-id "${snapshot_id}"
    echo "NOTE: Deleted snapshot ${snapshot_id}"
  fi
else
  echo "NOTE: No openclaw_mate_ami found, skipping"
fi


# ================================================================================
# PHASE 3: Destroy Core Infrastructure
# ================================================================================

echo "NOTE: Destroying core infrastructure..."

cd 01-core || {
  echo "ERROR: Directory 01-core not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# SECTION: Completion
# ================================================================================

echo "NOTE: Infrastructure teardown complete."

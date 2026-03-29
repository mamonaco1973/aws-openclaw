#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Orchestrate controlled teardown of core infrastructure.
#
# Teardown Order:
#     1. Destroy core infrastructure.
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

cd 02-openclaw || {
  echo "ERROR: Directory 02-openclaw not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 2: Destroy Core Infrastructure
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

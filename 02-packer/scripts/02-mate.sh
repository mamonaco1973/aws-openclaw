#!/bin/bash
set -euo pipefail

# ================================================================================
# MATE Desktop
# ================================================================================

export DEBIAN_FRONTEND=noninteractive

echo "NOTE: [mate] installing MATE desktop environment"
apt-get update -y
apt-get install -y ubuntu-mate-desktop

echo "NOTE: [mate] installing MATE utilities"
apt-get install -y \
  mate-terminal \
  mate-utils \
  xdg-utils

echo "NOTE: [mate] done"

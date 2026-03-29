#!/bin/bash
set -euo pipefail

# ================================================================================
# Node.js 22 + pnpm + OpenClaw
# ================================================================================
#
# Installs Node.js 22 system-wide via the NodeSource APT repository.
# Installs pnpm globally via npm and uses /opt/pnpm as the store.
# Installs openclaw globally so the binary is available at a fixed path.
#
# ================================================================================

echo "NOTE: [node] installing Node.js 22 via NodeSource"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
echo "NOTE: [node] Node $(node --version) installed"

echo "NOTE: [openclaw] installing openclaw globally via npm"
npm install -g openclaw
echo "NOTE: [openclaw] $(openclaw --version 2>&1 | head -1)"
echo "NOTE: [node] done"

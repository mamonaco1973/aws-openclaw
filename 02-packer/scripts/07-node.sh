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

echo "NOTE: [node] installing pnpm globally"
npm install -g pnpm
echo "NOTE: [node] pnpm $(pnpm --version) installed"

echo "NOTE: [openclaw] installing openclaw globally"
export PNPM_HOME=/opt/pnpm
export SHELL=/bin/bash
mkdir -p "${PNPM_HOME}"

PNPM_HOME="${PNPM_HOME}" pnpm add -g openclaw

# Approve any native builds non-interactively.
# 'a' toggles all checkboxes in pnpm's interactive approve-builds UI.
cd /opt/pnpm
printf 'a\n' | PNPM_HOME="${PNPM_HOME}" pnpm approve-builds -g || true

# Symlink into /usr/local/bin so the binary is in PATH system-wide.
ln -sf /opt/pnpm/openclaw /usr/local/bin/openclaw

echo "NOTE: [openclaw] $(openclaw --version 2>&1 | head -1)"
echo "NOTE: [node] done"

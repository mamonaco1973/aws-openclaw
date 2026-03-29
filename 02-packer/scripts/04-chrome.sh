#!/bin/bash
set -euo pipefail

# ================================================================================
# Google Chrome
# ================================================================================

echo "NOTE: [chrome] adding Google signing key"
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /usr/share/keyrings/google-linux-keyring.gpg

echo "NOTE: [chrome] adding Chrome APT repository"
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-keyring.gpg] \
https://dl.google.com/linux/chrome/deb/ stable main" \
  | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null

echo "NOTE: [chrome] installing Google Chrome Stable"
apt-get update -y
apt-get install -y google-chrome-stable

echo "NOTE: [chrome] $(google-chrome --version)"
echo "NOTE: [chrome] done"

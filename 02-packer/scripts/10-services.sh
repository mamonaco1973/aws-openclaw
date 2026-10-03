#!/bin/bash
set -euo pipefail

# ================================================================================
# Systemd Service Installation
# ================================================================================
#
# Installs litellm.service and openclaw-gateway.service but does NOT enable
# them. The image holds only a placeholder LiteLLM config (Claude only, from
# 09-openclaw-init.sh); enabled, LiteLLM came up on it at first boot, before
# userdata.sh wrote the real one, and every non-Claude model in
# bedrock-config.sh was rejected as "Invalid model name". userdata.sh enables
# and starts both after writing the real config; they stay enabled for later
# reboots. The gateway must stay disabled too: it Requires=litellm.service,
# so enabling it alone would pull LiteLLM up on the placeholder anyway.
#
# ================================================================================

echo "NOTE: [services] installing service unit files"
cp /tmp/litellm.service /etc/systemd/system/litellm.service
cp /tmp/openclaw-gateway.service /etc/systemd/system/openclaw-gateway.service
cp /tmp/xvfb.service /etc/systemd/system/xvfb.service

chmod 644 /etc/systemd/system/litellm.service
chmod 644 /etc/systemd/system/openclaw-gateway.service
chmod 644 /etc/systemd/system/xvfb.service

echo "NOTE: [services] reloading systemd daemon"
systemctl daemon-reload

echo "NOTE: [services] enabling xvfb (litellm and gateway are enabled by userdata.sh)"
systemctl enable xvfb
systemctl disable litellm openclaw-gateway 2>/dev/null || true

echo "NOTE: [services] setting up desktop icons"
mkdir -p /etc/skel/Desktop
mkdir -p /home/openclaw/Desktop
# VS Code's entry is com.microsoft.VSCode.desktop, not code.desktop -- the
# Microsoft package uses a reverse-DNS name. Under the old name the loop below
# printed its WARNING and the image shipped without a VS Code icon.
DESKTOP_APPS=(
  openclaw.desktop
  google-chrome.desktop
  com.microsoft.VSCode.desktop
  pcmanfm-qt.desktop
  qterminal.desktop
  onlyoffice-desktopeditors.desktop
)

for app in "${DESKTOP_APPS[@]}"; do
  src="/usr/share/applications/${app}"
  if [ -f "$src" ]; then
    ln -sf "$src" "/etc/skel/Desktop/${app}"
    ln -sf "$src" "/home/openclaw/Desktop/${app}"
  else
    echo "WARNING: ${app} not found, skipping"
  fi
done
chown -R openclaw:openclaw /home/openclaw/Desktop

echo "NOTE: [services] creating Openclaw symlink in home directories"
ln -sf /home/openclaw/.openclaw /home/openclaw/Openclaw
chown -h openclaw:openclaw /home/openclaw/Openclaw
ln -sf .openclaw /etc/skel/Openclaw

echo "NOTE: [services] done"

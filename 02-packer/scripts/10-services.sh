#!/bin/bash
set -euo pipefail

# ================================================================================
# Systemd Service Installation
# ================================================================================
#
# Installs litellm.service and openclaw-gateway.service and enables them so
# they start automatically at boot. Services are NOT started here — userdata.sh
# writes the litellm config with the actual Bedrock model ID before starting.
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

echo "NOTE: [services] enabling services for autostart at boot"
systemctl enable xvfb
systemctl enable litellm
systemctl enable openclaw-gateway

echo "NOTE: [services] done"

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

echo "NOTE: [mate] removing cloud-irrelevant packages"
apt-get purge -y \
  bluez \
  blueman \
  bluetooth \
  cups \
  cups-browsed \
  cups-common \
  cups-core-drivers \
  cups-daemon \
  cups-filters \
  system-config-printer \
  system-config-printer-common \
  printer-driver-postscript-hp \
  hplip \
  modemmanager \
  simple-scan \
  sane-utils \
  speech-dispatcher \
  speech-dispatcher-audio-plugins \
  orca \
  2>/dev/null || true
apt-get autoremove -y

echo "NOTE: [mate] disabling screensaver autostart (locks RDP session)"
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/mate-screensaver.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF

echo "NOTE: [mate] done"

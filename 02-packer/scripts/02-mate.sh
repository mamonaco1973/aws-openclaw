#!/bin/bash
set -euo pipefail

# ================================================================================
# LXQt Desktop
# ================================================================================

export DEBIAN_FRONTEND=noninteractive

echo "NOTE: [lxqt] installing LXQt desktop environment"
apt-get update -y
apt-get install -y \
  lxqt \
  lxqt-core \
  lxqt-config \
  lxqt-panel \
  lxqt-session \
  lxqt-policykit \
  lxqt-sudo \
  lxqt-runner \
  lxqt-notificationd \
  openbox \
  obconf-qt \
  pcmanfm-qt \
  qterminal

echo "NOTE: [lxqt] removing cloud-irrelevant and XRDP-conflicting packages"
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
  hplip \
  modemmanager \
  simple-scan \
  sane-utils \
  speech-dispatcher \
  speech-dispatcher-audio-plugins \
  orca \
  gvfs \
  gvfs-backends \
  gvfs-fuse \
  lxqt-powermanagement \
  libreoffice* \
  liblibreoffice* \
  update-notifier \
  update-notifier-common \
  ubuntu-advantage-desktop-daemon \
  2>/dev/null || true
apt-get autoremove -y

echo "NOTE: [lxqt] configuring LXQt session defaults"
mkdir -p /etc/xdg/lxqt
cat > /etc/xdg/lxqt/session.conf <<'EOF'
[Session]
window_manager=openbox
EOF

echo "NOTE: [lxqt] done"

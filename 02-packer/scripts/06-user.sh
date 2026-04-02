#!/bin/bash
set -euo pipefail

# ================================================================================
# OpenClaw Linux User
# ================================================================================
#
# Creates the 'openclaw' system user with sudo access.
# No password is set here — userdata.sh sets it from Secrets Manager at boot.
#
# ================================================================================

echo "NOTE: [user] creating openclaw user"
useradd -m -s /bin/bash openclaw
usermod -aG sudo openclaw

# Passwordless sudo — enables desktop admin actions without a password prompt.
echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw
chmod 440 /etc/sudoers.d/openclaw

echo "NOTE: [user] pre-configuring LXQt session (suppress window manager picker)"
mkdir -p /home/openclaw/.config/lxqt
cat > /home/openclaw/.config/lxqt/session.conf <<'EOF'
[General]
window_manager=openbox
EOF

echo "NOTE: [user] configuring pcmanfm-qt (suppress execute file dialog)"
mkdir -p /home/openclaw/.config/pcmanfm-qt/lxqt
cat > /home/openclaw/.config/pcmanfm-qt/lxqt/settings.conf <<'EOF'
[Desktop]
Wallpaper=/usr/share/lxqt/themes/debian/wallpaper.svg
WallpaperMode=zoom
WallpaperRandomize=false
ShowTrash=false
ShowMounts=false

[Behavior]
QuickExec=true
EOF

chown -R openclaw:openclaw /home/openclaw/.config

echo "NOTE: [user] creating openclaw Desktop directory"
mkdir -p /home/openclaw/Desktop
chown -R openclaw:openclaw /home/openclaw/Desktop

echo "NOTE: [user] done"

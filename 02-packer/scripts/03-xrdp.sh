#!/bin/bash
set -euo pipefail

# ================================================================================
# XRDP
# ================================================================================
#
# Installs XRDP and replaces /etc/xrdp/startwm.sh so all RDP logins launch
# a MATE session. Lowers color depth to 16bpp for better RDP performance.
#
# ================================================================================

export DEBIAN_FRONTEND=noninteractive

echo "NOTE: [xrdp] installing xrdp"
apt-get update -y
apt-get install -y xrdp

echo "NOTE: [xrdp] configuring MATE session"
tee /etc/xrdp/startwm.sh >/dev/null <<'EOF'
#!/bin/sh
if test -r /etc/profile; then
    . /etc/profile
fi

if test -r ~/.profile; then
    . ~/.profile
fi

mate-session
EOF
chmod 755 /etc/xrdp/startwm.sh

echo "NOTE: [xrdp] lowering color depth to 16bpp"
sed -i 's/^max_bpp=32/max_bpp=16/' /etc/xrdp/xrdp.ini

echo "NOTE: [xrdp] enabling xrdp service"
systemctl enable xrdp

echo "NOTE: [xrdp] configuring PAM for home directory creation on first login"
tee /etc/pam.d/xrdp-sesman >/dev/null <<'EOF'
#%PAM-1.0
auth required pam_env.so readenv=1
auth required pam_env.so readenv=1 envfile=/etc/default/locale
@include common-auth
@include common-account
@include common-session
@include common-password
EOF

echo "NOTE: [xrdp] disabling mate-power-manager (crashes on EC2 - no hardware power mgmt)"
mkdir -p /etc/xdg/autostart
cp /etc/xdg/autostart/mate-power-manager.desktop \
   /etc/xdg/autostart/mate-power-manager.desktop.bak 2>/dev/null || true
cat > /etc/xdg/autostart/mate-power-manager.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF

echo "NOTE: [xrdp] disabling MATE compositor (compositing over RDP tanks performance)"
mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/01-mate-performance <<'EOF'
[org/mate/marco/general]
compositing-manager=false
EOF
dconf update

echo "NOTE: [xrdp] done"

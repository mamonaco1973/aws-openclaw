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

echo "NOTE: [user] done"

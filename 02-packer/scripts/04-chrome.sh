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

echo "NOTE: [chrome] configuring flags for EC2 (no-sandbox, virtual display)"
# Wrap the chrome binary so --no-sandbox is always passed.
# Required in EC2 where user namespaces may be restricted.
mv /usr/bin/google-chrome /usr/bin/google-chrome-real
cat > /usr/bin/google-chrome <<'EOF'
#!/bin/bash
exec /usr/bin/google-chrome-real \
  --no-sandbox \
  --disable-dev-shm-usage \
  --no-first-run \
  --no-default-browser-check \
  --disable-sync \
  --disable-extensions \
  --disable-default-apps \
  "$@"
EOF
chmod 755 /usr/bin/google-chrome

echo "NOTE: [chrome] done"

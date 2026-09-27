#!/bin/bash
set -euo pipefail

# ================================================================================
# OpenClaw Config Initialization
# ================================================================================
#
# Runs the openclaw gateway briefly as the openclaw user to stamp the config
# file with internal metadata. Without this step, openclaw detects a
# "missing-meta-before-write" condition on first launch and overwrites any
# pre-written config with defaults, discarding the litellm provider settings.
#
# Flow:
#   1. Start litellm with a placeholder config so models auth can connect.
#   2. Run openclaw gateway in background as openclaw user (stamps config).
#   3. Configure the litellm model provider via CLI.
#   4. Stop both processes — config is persisted at /home/openclaw/.openclaw.
#
# ================================================================================

# The two models below are placeholders so the gateway has something to stamp
# against at build time. They are NOT the deployed list: userdata.sh rewrites
# this file and re-registers the models from bedrock-config.sh at first boot,
# so they need not track that file -- but keep them to ids that exist.
echo "NOTE: [openclaw-init] writing placeholder litellm config"
mkdir -p /opt/openclaw
cat > /opt/openclaw/litellm-config.yaml <<'LITELLM'
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-east-1

  - model_name: claude-haiku
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-east-1

general_settings:
  master_key: "sk-openclaw"
  drop_params: true
LITELLM
chown openclaw:openclaw /opt/openclaw/litellm-config.yaml

echo "NOTE: [openclaw-init] starting litellm placeholder"
sudo -u openclaw /opt/litellm-venv/bin/litellm \
  --config /opt/openclaw/litellm-config.yaml --port 4000 &
LITELLM_PID=$!
sleep 8

OPENCLAW_BIN=$(which openclaw)
echo "NOTE: [openclaw-init] openclaw binary: ${OPENCLAW_BIN}"

echo "NOTE: [openclaw-init] starting openclaw gateway to stamp config metadata"
sudo -u openclaw env HOME=/home/openclaw PATH="${PATH}" bash -c "
  ${OPENCLAW_BIN} gateway run \
    --allow-unconfigured --bind loopback --port 18789 &
  echo \$! > /tmp/openclaw-init.pid
"
sleep 12

echo "NOTE: [openclaw-init] configuring litellm model provider"
sudo -u openclaw env HOME=/home/openclaw PATH="${PATH}" bash -c "
  ${OPENCLAW_BIN} config set gateway.mode local || true
  ${OPENCLAW_BIN} config set gateway.auth.mode none || true
  ${OPENCLAW_BIN} config set models.providers.litellm \
    '{\"baseUrl\":\"http://localhost:4000\",\"apiKey\":\"sk-openclaw\",\"models\":[{\"id\":\"claude-sonnet\",\"name\":\"Claude Sonnet\"},{\"id\":\"claude-haiku\",\"name\":\"Claude Haiku\"}]}' \
    --strict-json || true
  ${OPENCLAW_BIN} models set litellm/claude-haiku || true
  ${OPENCLAW_BIN} models set litellm/claude-sonnet || true
  ${OPENCLAW_BIN} config set agents.defaults.model.primary litellm/claude-haiku || true
  ${OPENCLAW_BIN} approvals allowlist add --agent '*' '/**' || true
  ${OPENCLAW_BIN} approvals allowlist add --agent 'main' '/**' || true
"

echo "NOTE: [openclaw-init] stopping all openclaw and litellm processes"
# Kill all processes running as the openclaw user — this catches the gateway,
# any restarted child processes, node workers, and uvicorn/litellm children
# that pkill -f misses.
pkill -u openclaw 2>/dev/null || true
sleep 3
# Force-kill anything still alive
pkill -9 -u openclaw 2>/dev/null || true
rm -f /tmp/openclaw-init.pid

echo "NOTE: [openclaw-init] writing workspace files"
WORKSPACE=/home/openclaw/.openclaw/workspace
mkdir -p "${WORKSPACE}"

cat > "${WORKSPACE}/HEARTBEAT.md" <<'HEARTBEAT'
# System Context

You are running on an AWS EC2 instance with the following capabilities:

- **exec tool**: Full shell access — use it to run commands directly. Never ask the user to run commands manually.
- **AWS CLI**: Pre-authenticated via instance IAM role. No credentials needed. Run aws commands directly via exec.
- **Cost Explorer**: Use `aws ce get-cost-and-usage` — the IAM role has Cost Explorer access.
- **Web**: Apache2 serves /var/www/html (world-writable) at http://localhost/ — write a file there and open it in the browser.

Read SYSTEM.md in this workspace for the full list of installed tools and capabilities.
HEARTBEAT

# Email is NOT described here. It exists only when 01-core created the SES
# secret, which the image cannot know; userdata.sh appends the Email section
# to HEARTBEAT.md and SYSTEM.md at boot when it finds SMTP credentials.
echo "NOTE: [openclaw-init] writing SYSTEM.md to workspace"
cat > "${WORKSPACE}/SYSTEM.md" <<'SYSTEM'
# System Capabilities

This instance has the following tools and capabilities available via exec.

## Web publishing
Apache2 is installed and running. The document root is `/var/www/html`, and it
is world-writable, so you can publish a page with the exec tool and no sudo:

```bash
echo "<h1>hello</h1>" > /var/www/html/index.html
```

It is then served at http://localhost/ — open that with the browser tool to
show the user the result. Port 80 is not reachable from outside the instance,
so this is for showing things on the desktop, not for publishing to the web.

Anything self-contained works: a single HTML file, or HTML plus CSS and
JavaScript. Write the files, then open the page to demonstrate it.


## Document Processing
- **python-docx** — read/write Word documents
- **python-pptx** — read/write PowerPoint files
- **openpyxl** — read/write Excel files
- **pymupdf** — read/extract PDF content
- **reportlab** — generate PDFs
- **pandoc** — convert between document formats
- **OnlyOffice** — desktop app for editing DOCX/XLSX/PPTX files

## Data & Analysis
- **pandas**, **numpy** — data analysis
- **matplotlib** — charts and visualizations
- **sqlite3** — local database

## Web & HTTP
- **curl**, **wget** — HTTP requests
- **beautifulsoup4**, **lxml** — HTML parsing
- **httpx**, **requests** — Python HTTP

## Media
- **imagemagick** — image manipulation (convert, resize, crop)
- **ffmpeg** — video/audio processing
- **poppler-utils** — PDF utilities (pdftotext, pdfinfo)
- **ghostscript** — PDF manipulation

## Cloud
- **AWS CLI** — configured via instance IAM role (no credentials needed)
  - Bedrock, S3, Cost Explorer, Secrets Manager, SES
- **Terraform**, **Packer** — infrastructure tools
- **gcloud**, **az** — Google Cloud and Azure CLIs

## File System
- Workspace: `~/.openclaw/workspace` (also accessible as `~/Openclaw/workspace`)
- Home: `/home/openclaw`

## Utilities
- **jq** — JSON processing
- **csvkit** — CSV tools
- **xmlstarlet** — XML processing
- **Rich** (Python) — formatted terminal output

SYSTEM

chown -R openclaw:openclaw "${WORKSPACE}"

echo "NOTE: [openclaw-init] appending SYSTEM.md reference to BOOTSTRAP.md"
BOOTSTRAP="${WORKSPACE}/BOOTSTRAP.md"
if [ -f "${BOOTSTRAP}" ]; then
  cat >> "${BOOTSTRAP}" <<'EOF'

---

## This System

Before you delete this file, read `SYSTEM.md` in this workspace — it lists
the tools, commands, and capabilities available on this machine (email, document
processing, AWS CLI, etc.). Keep that file around after onboarding.
EOF
fi

echo "NOTE: [openclaw-init] config directory contents:"
ls -la /home/openclaw/.openclaw/ 2>/dev/null || echo "(empty)"

echo "NOTE: [openclaw-init] done"

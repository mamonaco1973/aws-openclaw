# CLAUDE.md — aws-openclaw

## Project Overview

Terraform + Packer project that deploys an EC2 instance running **OpenClaw**
(an AI coding agent) backed by **LiteLLM proxy** pointed at **AWS Bedrock**.
Users RDP into an LXQt desktop and access the OpenClaw web UI at
`http://localhost:18789` in Chrome. No SSH keys. RDP is open directly on port
3389 (`openclaw-sg` allows it from anywhere); SSM Session Manager
port-forwarding also works if you would rather close that rule.

The README architecture diagram is generated: edit `make_diagram.py` and run
`python make_diagram.py`, which rewrites `architecture-{light,dark}.svg`.

## Architecture

```
01-core/          VPC + subnets + NAT gateway + SES (optional)
02-packer/        Packer build: Ubuntu 24.04 → openclaw_ami
  scripts/        01-packages through 14-apache (13 unused; 09, 10 run last)
  files/          litellm/openclaw-gateway/xvfb services, openclaw.png
03-openclaw/      EC2 instance + IAM role + security group + secrets
  scripts/
    userdata.sh   Boot: set password from secret, write litellm config,
                  email if SES exists, start services, register models
```

### Deployment Order

1. `01-core` — VPC, subnets, NAT gateway; SES identity + SMTP secret when
   `ses_email` is set
2. `02-packer` — Packer builds `openclaw_ami`
3. `03-openclaw` — EC2 from `openclaw_ami`, secrets, IAM

### Key Resources

| Resource | Value |
|---|---|
| Region | `us-east-1` |
| VPC / CIDR | `clawd-vpc` / `10.0.0.0/23` |
| EC2 instance tag | `openclaw-host` |
| Instance type | `t3.xlarge` (variable) |
| LiteLLM port | `4000` |
| LiteLLM master key | `sk-openclaw` |
| OpenClaw gateway port | `18789` (loopback only) |
| Bedrock models | From `bedrock-config.sh`; region `us-east-1` |
| Linux user | `openclaw` (sudo, NOPASSWD) |
| Password source | AWS Secrets Manager `openclaw_credentials` |

## Common Commands

```bash
# Validate environment: CLI tools, AWS auth, and every model in
# bedrock-config.sh answering on Bedrock
./check_env.sh

# Deploy everything (01-core → 02-packer → 03-openclaw → validate)
./apply.sh

# Tear down (03-openclaw → deregister AMI → 01-core)
./destroy.sh

# Validate post-deploy
./validate.sh

# See which Bedrock models this account can actually call, ranked by latency
./probe_bedrock.py
```

### Connecting to the Instance

```bash
# Get instance ID
INSTANCE_ID=$(cd 03-openclaw && terraform output -raw instance_id)

# SSM shell session
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1

# RDP port-forward (then connect to localhost:13389)
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3389"],"localPortNumber":["13389"]}' \
  --region us-east-1
```

### Getting the openclaw User Password

```bash
aws secretsmanager get-secret-value \
  --secret-id openclaw_credentials \
  --query SecretString \
  --output text | jq -r '.password'
```

## What Packer (02-packer) Does

Builds `openclaw_ami` from Ubuntu 24.04 (fully self-contained):

| Script | What it installs |
|---|---|
| `01-packages.sh` | apt retry helper, removes snap, installs SSM agent DEB, base packages |
| `02-desktop.sh` | LXQt desktop environment |
| `03-xrdp.sh` | XRDP + LXQt session config |
| `04-chrome.sh` | Google Chrome Stable, with the real sandbox (no `--no-sandbox`) |
| `05-tools.sh` | Git, AWS CLI v2, Terraform, Packer, Azure CLI, gcloud, VS Code |
| `06-user.sh` | `openclaw` Linux user with passwordless sudo |
| `07-node.sh` | Node.js 22, OpenClaw, `openclaw-dashboard` desktop launcher |
| `08-litellm.sh` | Python venv at `/opt/litellm-venv`, `litellm[proxy]` |
| `11-python-tools.sh` | Pinned Python packages and system utilities |
| `12-onlyoffice.sh` | OnlyOffice Desktop Editors |
| `14-apache.sh` | Apache2 serving world-writable `/var/www/html` on loopback |
| `09-openclaw-init.sh` | Stamps gateway config; writes `HEARTBEAT.md`/`SYSTEM.md` |
| `10-services.sh` | Installs and enables the systemd units |

Every build script installs through `apt-install-retry` (created by
`01-packages.sh`), not `apt-get install`. `security.ubuntu.com` servers are
briefly out of step while a security update publishes, which surfaces as a
random `404 Not Found`; the helper re-reads the index and retries. Use it in
any new build script.

Note the provisioner order is not the filename order: `09` and `10` run last,
because the gateway must be stamped after everything it advertises exists.
`13` is unused here; in gcp-openclaw it is the GCP-only infra-report tooling.

Email is deliberately absent from the image's agent notes. SES is optional, so
`userdata.sh` appends the Email section to `HEARTBEAT.md` and `SYSTEM.md` only
when the `openclaw_ses_smtp` secret exists.

## What userdata.sh Does

Runs at first boot on the `openclaw_ami` EC2 instance:

1. Reads `openclaw_credentials` from Secrets Manager via instance IAM role
2. Sets the `openclaw` Linux user password (`chpasswd`)
3. Renders `/opt/openclaw/litellm-config.yaml`, one `model_list` entry per
   model in `bedrock-config.sh`
4. If the `openclaw_ses_smtp` secret exists: writes msmtp config, injects the
   SMTP settings into the gateway service, and appends the Email section to
   the agent's `HEARTBEAT.md`/`SYSTEM.md`
5. Starts `litellm.service` and `openclaw-gateway.service`
6. Registers every model with OpenClaw, sets the primary, and restarts the
   gateway

## Model Configuration

`bedrock-config.sh` is the single source of truth. It defines a
`BEDROCK_MODELS` array of `alias|bedrock-model-id|display name`, plus
`BEDROCK_PRIMARY` and `BEDROCK_REGION`, and exports them to Terraform as
`TF_VAR_models`, `TF_VAR_primary_alias`, and `TF_VAR_bedrock_region`.

Everything derives from that one array: the LiteLLM `model_list`, the OpenClaw
model picker (registered by `userdata.sh`, overriding the placeholder models
`09-openclaw-init.sh` bakes into the AMI), and the `check_env.sh` pre-flight.
Any number of entries from 1 upward renders correctly.

**Why aliases.** The alias is what LiteLLM routes on and what OpenClaw stores
as the model ID. Changing the Bedrock ID behind an alias does not repoint
existing agents.

**Why the probe.** An inference profile can be ACTIVE and still return
AccessDenied for a given account. The only reliable test is to make the call.
`check_env.sh` runs `probe_bedrock.py --check` on every ID before any resource
is created; run `./probe_bedrock.py` to see everything the account can serve.

## IAM Permissions

The instance role (`openclaw-role`) has:

| Policy | Purpose |
|---|---|
| `AmazonSSMManagedInstanceCore` | SSM Session Manager access |
| Inline `openclaw-bedrock` | `bedrock:InvokeModel` + `InvokeModelWithResponseStream` on foundation models and inference profiles |
| Inline `openclaw-secrets` | `secretsmanager:GetSecretValue` scoped to `openclaw_credentials*` and `openclaw_ses_smtp*` |
| Inline `openclaw-ses` | `ses:SendEmail` + `ses:SendRawEmail` (mail itself goes through the SMTP user in 01-core) |
| Inline `openclaw-cost-explorer` | Cost Explorer read APIs, resource `*` (the service requires it) |

## Networking Design

- `vm-subnet-1` / `vm-subnet-2` — private workload subnets, egress via NAT
- `pub-subnet-1` / `pub-subnet-2` — public subnets (NAT gateway + Packer builder)
- Security group `openclaw-sg` — port 3389 inbound, all outbound allowed
- Apache listens on 80 but no rule opens it — deliberately loopback only, for
  showing pages on the desktop
- **Packer build uses `pub-subnet-1`** (needs SSH from internet during build)
- **EC2 host uses `pub-subnet-1`** (direct RDP access)

## Password Format

Generated by Terraform in `03-openclaw/accounts.tf`:

```
<word>-<6-digit-number>   e.g. "rocket-482910"
```

Stored in Secrets Manager as `{"username": "openclaw", "password": "..."}`.

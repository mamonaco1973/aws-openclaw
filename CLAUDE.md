# CLAUDE.md — aws-openclaw

## Project Overview

Terraform project that deploys an EC2 instance running **OpenClaw** (an AI coding agent) backed by **LiteLLM proxy** pointed at **AWS Bedrock**. No SSH keys, no open inbound ports — all access via AWS Systems Manager (SSM) Session Manager.

## Architecture

```
01-core/          VPC + subnets + NAT gateway
02-openclaw/      EC2 instance + IAM role + security group
  scripts/
    userdata.sh   Bootstrap: SSM agent, Node 22, pnpm, OpenClaw, LiteLLM systemd service
```

### Deployment Order

`01-core` must be applied before `02-openclaw`. The second module resolves networking via data sources keyed on Name tags (`clawd-vpc`, `vm-subnet-1`).

### Key Resources

| Resource | Value |
|---|---|
| Region | `us-east-1` |
| VPC CIDR | `10.0.0.0/23` |
| EC2 instance tag | `openclaw-host` |
| Instance type | `t3.medium` (variable) |
| LiteLLM port | `4000` |
| LiteLLM master key | `sk-openclaw` |
| Bedrock model | `anthropic.claude-sonnet-4-5` |

## Common Commands

```bash
# Validate environment (checks aws, terraform, jq, packer in PATH + AWS auth)
./check_env.sh

# Deploy everything (01-core -> 02-openclaw -> validate)
./apply.sh

# Tear down (02-openclaw first, then 01-core)
./destroy.sh

# Validate post-deploy
./validate.sh
```

### Manual Terraform (per module)

```bash
cd 01-core && terraform init && terraform apply -auto-approve
cd 02-openclaw && terraform init && terraform apply -auto-approve
```

### Connecting to the Instance

No SSH. Use SSM Session Manager with the instance ID from Terraform output:

```bash
INSTANCE_ID=$(cd 02-openclaw && terraform output -raw instance_id)
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1
```

## What userdata.sh Does

Runs at first boot on Ubuntu 24.04:

1. Installs `curl`, `unzip`, `python3-pip`, `python3-venv`
2. Installs and starts the **SSM agent** (not pre-installed on Ubuntu)
3. Installs **Node.js 22** via NodeSource
4. Installs **pnpm** and sets `PNPM_HOME`
5. Installs **OpenClaw** globally via pnpm (`openclaw@latest`)
6. Creates a Python virtualenv at `/opt/litellm-venv` and installs `litellm[proxy]`
7. Writes `/etc/litellm/config.yaml` pointing at Bedrock `anthropic.claude-sonnet-4-5`
8. Registers and starts a **`litellm.service`** systemd unit on port 4000

## IAM Permissions

The instance role (`openclaw-role`) has:
- `AmazonSSMManagedInstanceCore` — SSM Session Manager access
- Inline policy `openclaw-bedrock` — `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on all foundation models

## Networking Design

- `vm-subnet-1` / `vm-subnet-2` — private utility subnets, egress via NAT gateway
- `pub-subnet-1` / `pub-subnet-2` — public subnets hosting the NAT gateway
- Security group `openclaw-sg` — **no inbound rules**, all outbound allowed
- Instance access exclusively through SSM (no key pairs, no open ports)

## Modifying the Bedrock Model

Edit the model name in [02-openclaw/scripts/userdata.sh](02-openclaw/scripts/userdata.sh) under the `model_list` section of the LiteLLM config heredoc. The format is `bedrock/<model-id>`. After changing, re-deploy the instance (taint or recreate).

## validate.sh

Currently fully commented out — it references RStudio/AD resources from a prior project iteration and has not been updated for this OpenClaw deployment.

## Prerequisites

- AWS CLI configured with IAM permissions for EC2, IAM, VPC, Bedrock, SSM
- Terraform installed
- jq installed
- packer installed (checked by `check_env.sh`, not used in current build)
- Bedrock model access enabled in `us-east-1` for `anthropic.claude-sonnet-4-5`
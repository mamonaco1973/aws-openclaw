# configure.md — Post-Deploy OpenClaw Setup

Steps to complete after `./apply.sh` finishes and the EC2 instance has finished
running userdata. Allow ~3-5 minutes after apply for userdata to complete.

---

## 1. Connect to the Instance

```bash
INSTANCE_ID=$(cd 02-openclaw && terraform output -raw instance_id)
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1
```

Become root:

```bash
sudo bash
```

---

## 2. Verify Userdata Completed

```bash
tail /root/userdata.log
```

The last line should read:

```
NOTE: Userdata script completed.
```

If it hasn't finished yet, follow it live:

```bash
tail -f /root/userdata.log
```

---

## 3. Load the pnpm PATH

SSM sessions don't source `.bashrc` automatically:

```bash
export PNPM_HOME="/root/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
```

---

## 4. Verify LiteLLM is Running

```bash
systemctl status litellm
curl -s http://localhost:4000/health
```

Both should show healthy. If litellm is not running:

```bash
systemctl restart litellm
journalctl -u litellm -n 50
```

---

## 5. Run OpenClaw Onboarding

```bash
export LITELLM_API_KEY="sk-openclaw"
openclaw onboard --auth-choice litellm-api-key
```

Answer the prompts as follows:

| Prompt | Answer |
|---|---|
| Security acknowledgment | **Yes** |
| Setup mode | **QuickStart** |
| Use existing LITELLM_API_KEY? | **Yes** |
| Select channel | **Skip for now** |
| Search provider | **DuckDuckGo Search (experimental)** |
| Configure skills now? | **No** |
| Configure hooks now? (if prompted) | **No** |

Onboarding writes config to `~/.openclaw/openclaw.json` and exits.

---

## 6. Set the Default Model

```bash
openclaw models set litellm/claude-sonnet
```

Verify:

```bash
openclaw models status
```

---

## 7. Start the Gateway

```bash
openclaw gateway run
```

The gateway runs in the foreground. You should see:

```
[gateway] agent model: litellm/claude-sonnet
[gateway] listening on ws://127.0.0.1:18789 ...
```

---

## 8. Test the Agent (Second SSM Session)

Open a second SSM session to the same instance and repeat steps 2-3, then:

```bash
openclaw agent --agent main --message "hello"
```

A successful response from the model confirms end-to-end connectivity:
SSM → OpenClaw gateway → LiteLLM proxy → Bedrock → Claude.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `openclaw: command not found` | Re-export pnpm PATH (step 3) |
| LiteLLM returns 400 invalid model | Check `systemctl status litellm` and verify the model ID in `/etc/litellm/config.yaml` matches what Bedrock returned during apply |
| `Pass --to or --session-id` error | Use `--agent main` flag |
| Gateway shows `litellm/claude-opus-4-6` | Run step 6 to override the model |
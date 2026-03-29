# configure.md — Post-Deploy OpenClaw Setup

Steps to complete after `./apply.sh` finishes. Allow ~5 minutes for userdata
to complete (Docker image pulls take the bulk of that time).

---

## 1. Connect to the Instance

```bash
INSTANCE_ID=$(cd 02-openclaw && terraform output -raw instance_id)
aws ssm start-session --target "$INSTANCE_ID" --region us-east-1
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

## 3. Verify Containers Are Running

```bash
docker compose -f /opt/openclaw/docker-compose.yml ps
```

Both `litellm` and `openclaw` should show `running`. If either is not up:

```bash
docker compose -f /opt/openclaw/docker-compose.yml logs
```

---

## 4. Test the Agent

```bash
docker exec openclaw node dist/index.js agent --agent main --message "hello"
```

A successful reply from the model confirms end-to-end connectivity:
EC2 instance → OpenClaw gateway → LiteLLM → Bedrock → Claude.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Container `openclaw` keeps restarting | Check logs: `docker compose -f /opt/openclaw/docker-compose.yml logs openclaw` |
| LiteLLM 401 / auth error | Verify `sk-openclaw` key matches in `/opt/openclaw/litellm-config.yaml` and `/opt/openclaw/config/openclaw.json` |
| Bedrock 403 / credentials error | IMDSv2 hop limit may not have applied — run `terraform apply` again to force instance recreation |
| Invalid model name | Check the resolved model ID: `grep model /opt/openclaw/litellm-config.yaml` and verify it is enabled in Bedrock console |
| Need to change the model | Update `/opt/openclaw/litellm-config.yaml`, then `docker compose -f /opt/openclaw/docker-compose.yml restart litellm` |
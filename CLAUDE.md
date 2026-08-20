# CLAUDE.md — security_onion_ai

## What this repo is
A Terraform-deployed Azure lab running Security Onion 2.4.201 (STANDALONE,
Marketplace image) for detection engineering against self-generated attack
traffic. Existing work: network-layer attack simulation via attack.sh.

## What we're adding (this branch)
A DC862 talk (Sept 4): detecting Linux persistence using a custom MCP server +
Claude Desktop to query Security Onion's Elasticsearch. The lab has network
telemetry only; persistence lives on hosts. We add: an endpoint telemetry layer
(Elastic Fleet + Elastic Defend + auditd/FIM), a new attack stage
(persistence.sh), and an AI query layer (the MCP server). Persistence detection
bypasses the Azure inter-VM mirroring limitation (README VNET TAP challenge) — it
relies on the endpoint agent on the victim, not the passive monitoring NIC.

## Lab facts (use these exact values — do not invent)
- Resource group: so-ai-lab-rg
- SO management (eth0): 10.0.1.10
- SO monitoring NIC (eth1): 10.0.2.10  (passive; attack.sh targets this)
- Attacker VM: 10.0.2.20
- Victim VM (persistence target): 10.0.2.30
- Admin user: labadmin
- SSH key: ~/.ssh/so-lab-key.pem
- VM size: B4ms (8 vCPU quota total)
- Existing attack script: ~/attacks/attack.sh on attacker, targets 10.0.2.10
- SOC console: https://<SO_PUBLIC_IP> (self-signed; Chrome/Firefox, not Brave)

## Persistence techniques in scope (5, Linux-native, run on victim 10.0.2.30)
Each stage carries its ATT&CK ID in a comment.
1. ~/.bashrc / ~/.profile append — T1546.004 (headline "login script")
2. cron job in /etc/cron.d/ — T1053.003
3. systemd service + timer — T1543.002
4. SSH authorized_keys implant — T1098.004
5. new user + sudoers entry — T1136.001
Windows persistence is OUT of scope (future work on the closing slide).

## FIM / auditd watch paths (must exist or detections return nothing)
/etc/cron.*, /etc/systemd/system/, ~/.bashrc, ~/.profile,
~/.ssh/authorized_keys, /etc/passwd, /etc/sudoers.d/

## Elasticsearch / ECS conventions
- SO 2.4 uses ECS data streams. Likely endpoint index patterns:
  logs-endpoint.events.process-*, logs-endpoint.events.file-*,
  logs-endpoint.events.network-*, auditd via logs-auditd*-*.
- DO NOT hardcode index or field names from memory. Confirm real names in the SOC
  console (Hunt/Kibana) or via the MCP list_indices tool, then write detections
  against confirmed values.
- ECS fields: event.category, event.action, process.name, process.command_line,
  process.args, process.parent.name, file.path, host.ip, user.name, @timestamp.

## MCP server rules (mandatory — also shown live as a talking point)
- Transport: stdio (connects to Claude Desktop). Use FastMCP (Python mcp SDK).
- Exactly two tools: list_indices and search (accepts ES DSL or EQL).
- Guardrails, all four, visible in code: read-only ES user, index allowlist,
  hard size cap, query timeout.
- Put a compact schema summary (confirmed index names + key ECS fields) in the
  search tool description so the model doesn't invent fields.
- Never commit ES credentials. .env.example only.

## Safety / scope
Benign, lab-only techniques against a self-owned isolated victim VM. No
exfiltration, no real C2, no destructive actions. The .bashrc beacon is an
echo/curl to a lab-internal address. persistence.sh must be idempotent and ship a
--cleanup that fully reverses every stage.

## What Claude Code must NOT do
- Do not run Terraform, deploy to Azure, enroll Fleet agents, or execute
  persistence.sh. Those are live-infra steps the human runs. Scaffold + document.
- Do not generate slides — the deck is done.
- Do not commit secrets, ES creds, or terraform.tfvars.

## Conventions
- Branch: feat/endpoint-persistence-detection. Commit in logical chunks.
- Match attack.sh style: set -euo pipefail, echoed stage banners, sudo where needed.
- New files: persistence.sh next to attack.sh; queries under queries/; MCP server
  under mcp-server/; ops docs under docs/.

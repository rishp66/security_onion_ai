# Endpoint telemetry setup (manual — human runs these)

Adds a host-based telemetry layer to the victim VM (10.0.2.30) so persistence
techniques are visible even though Azure inter-VM mirroring only covers
network traffic (see README VNET TAP challenge). Claude Code does not run
these steps — they touch live infra.

## 1. Enroll victim in Elastic Fleet (via SO manager)

1. SOC console → Administration → Grid → confirm SO 2.4.201 Fleet/Elastic
   Agent is enabled on the manager.
2. Grid → Fleet → generate an enrollment token for the victim host.
3. On victim (10.0.2.30), install and enroll the Elastic Agent using that
   token, pointed at the SO manager's Fleet server (10.0.1.10).
4. Confirm the agent shows "Healthy" in Fleet → Agents.

## 2. Enable Elastic Defend integration

1. Fleet → Agent Policies → policy assigned to the victim → Add integration
   → Elastic Defend.
2. Enable process, file, and network event collection at minimum.
3. Confirm events start flowing: SOC console → Hunt → filter
   `event.module: endpoint`.

## 3. auditd / FIM watch rules

Ensure these paths are watched (via Elastic Defend FIM or auditd rules —
whichever SO 2.4.201 exposes for this integration):

```
/etc/cron.*
/etc/systemd/system/
~/.bashrc
~/.profile
~/.ssh/authorized_keys
/etc/passwd
/etc/sudoers.d
```

If using raw auditd rules (`/etc/audit/rules.d/persistence.rules`), a
starting point:

```
-w /etc/cron.d -p wa -k persistence_cron
-w /etc/systemd/system -p wa -k persistence_systemd
-w /etc/passwd -p wa -k persistence_user
-w /etc/sudoers.d -p wa -k persistence_sudoers
-w /root/.ssh/authorized_keys -p wa -k persistence_ssh
-w /root/.bashrc -p wa -k persistence_bashrc
```

TODO: confirm SO 2.4.201's actual auditd/Elastic Defend FIM config path —
don't hand-edit rules blind, check what the integration already ships.

## 4. Confirm index names before writing detections

Do not hardcode index/field names from memory. In SOC console → Hunt or
Kibana Discover, check what actually landed. Likely candidates:
`logs-endpoint.events.process-*`, `logs-endpoint.events.file-*`,
`logs-endpoint.events.network-*`, `logs-auditd*-*`. Update
`mcp-server/server.py` (`ALLOWED_INDEX_PATTERNS`) and
`queries/persistence_queries.md` once confirmed.

## 5. Run the attack

```bash
ssh -i ~/.ssh/so-lab-key.pem labadmin@10.0.2.30
sudo bash persistence.sh
```

Wait 2-3 min, hunt via SOC console or the MCP server + Claude Desktop.
Reverse everything with:

```bash
sudo bash persistence.sh --cleanup
```

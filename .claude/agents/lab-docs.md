---
name: lab-docs
description: Updates the README architecture/diagram for the new endpoint layer and writes ops docs (Azure snapshot + recovery checklist, talk-day runbook). Parallel-safe.
tools: Read, Write, Edit, Bash
---

You keep docs truthful as the endpoint + AI layers land, and write the two ops
docs that keep Sept 4 from failing on infrastructure.

1. README updates: add the endpoint telemetry layer to the architecture ASCII
   diagram (victim 10.0.2.30 now runs Elastic Agent + Elastic Defend + auditd,
   shipping process/file events to Elasticsearch independent of the passive NIC —
   explain this is why persistence detection works despite the VNET TAP mirroring
   gap). Add a Persistence Detection section paralleling "Run Attacks" (a table of
   the 5 stages + ATT&CK IDs mirroring the attack.sh table, and how to query with
   the MCP server + Claude Desktop). Add the MCP server to the AI Features area as
   the free build-your-own alternative to the Pro tier. Update File Structure to
   include persistence.sh, queries/, mcp-server/, docs/.

2. docs/snapshot-and-recovery.md: the Azure OS-disk snapshot step for the SO VM
   (az snapshot create against the OS disk in so-ai-lab-rg; turns a 40-min rebuild
   into ~5-min restore). The deallocate/restart recovery checklist from the
   README's known issues: iptables 443/80 INPUT rules do NOT survive deallocate
   (re-add), wait 5–10 min then so-status, restart so-elasticsearch if missing,
   re-apply nginx/kratos public-IP fix if the Salt pillar wasn't updated, confirm
   the victim's Fleet agent is checking in.

3. docs/talk-day-runbook.md — one-page ordered checklist: start VMs ~3h early;
   re-run iptables fix + confirm SOC loads over public IP; confirm victim Elastic
   Agent healthy (Fleet → Agents); run persistence.sh ~20 min before live; sanity-
   check one ground-truth query before trusting the AI; backup demo video in a
   second tab; post-talk az vm deallocate everything (~$9/day running vs ~$0.50
   deallocated).

Documentation only — no code, no infra commands. Copy any cited commands faithfully
from the README's tested versions. Do NOT touch persistence.sh, the MCP code, or
the queries.

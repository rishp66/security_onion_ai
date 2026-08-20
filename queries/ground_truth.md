# Ground-truth detection queries — DC862 persistence demo

These are hand-written, human-verified detections for the 5 persistence
techniques planted by `persistence.sh` on the victim VM (10.0.2.30). They
exist for two reasons:

1. **Validation** — ground truth to check the AI/MCP query layer's answers
   against during rehearsal, so we know if the model is finding real
   evidence or hallucinating.
2. **On-stage fallback** — if the live AI demo fails or times out, these
   queries paste directly into SOC Hunt / Kibana Dev Tools and get us the
   same result manually.

**Nothing in this file is cluster-confirmed.** No live Elasticsearch has
been queried this session. Every index pattern and field name below is
carried over from CLAUDE.md's *candidate* list or standard ECS conventions
and is marked `TODO: verify` accordingly. Before the talk, run each query
against the real SO 2.4.201 cluster (via SOC Hunt/Kibana or the MCP
`list_indices` tool) and strike the TODOs for whatever is confirmed —
correct any field/index that doesn't match.

Artifact values below are pulled directly from `persistence.sh`, not
guessed:
- Beacon host: `10.0.1.10` (SO management NIC, `LAB_BEACON_HOST`)
- Shared marker string: `# dc862-persistence-demo` (`$MARKER`)
- Implant user: `labsvc` (`$IMPLANT_USER`)
- Cron file: `/etc/cron.d/system-health-check`
- systemd unit base name: `system-metrics-agent` (`.service` + `.timer`)
- SSH implant key comment: `dc862-demo-implant`
- Sudoers file: `/etc/sudoers.d/90-labsvc`

---

## 1. Shell profile beacon — T1546.004

**What to look for:** a file-write to `/root/.bashrc` or `/root/.profile`
that adds the shared marker line and a background `curl` beacon to the lab
management host.

**Index:** `logs-endpoint.events.file-*` (Elastic Defend FIM) — TODO: verify
this is the real data stream name and not `logs-auditd*-*` if FIM is being
sourced from auditd's watch on `~/.bashrc` / `~/.profile` instead.

**Query (DSL — pure file-write case):**
```json
{
  "query": {
    "bool": {
      "filter": [
        { "terms": { "file.path": ["/root/.bashrc", "/root/.profile"] } },
        { "terms": { "event.action": ["modification", "creation", "change"] } }
      ],
      "should": [
        { "match_phrase": { "file.path": "dc862-persistence-demo" } }
      ]
    }
  }
}
```
TODO: verify `event.action` vocabulary for this integration (`modification`
vs `modified`/`change` varies by ECS integration) and whether file *content*
is indexed anywhere to match on the marker string directly.

**Key field:** `file.path` — this is the only field guaranteed to
distinguish "someone edited root's login shell profile" from routine
file activity; the marker string is a nice-to-have confirmation but isn't
guaranteed to be indexed as searchable content.

---

## 2. Cron persistence — T1053.003

**What to look for:** creation of `/etc/cron.d/system-health-check`, a new
cron file dropped outside the user's own crontab.

**Index:** `logs-endpoint.events.file-*` — TODO: verify; `logs-auditd*-*`
is the likely alternate source per the auditd watch path on `/etc/cron.*`
listed in CLAUDE.md.

**Query (DSL — pure file-write case):**
```json
{
  "query": {
    "bool": {
      "filter": [
        { "wildcard": { "file.path": "/etc/cron.d/*" } },
        { "term": { "event.action": "creation" } }
      ]
    }
  }
}
```
TODO: verify `event.action` value for "creation" in this integration, and
confirm `file.path` is not instead `file.name` + `file.directory` split
fields in the mapping actually in use.

**Key field:** `file.path` matched against `/etc/cron.d/*` — this path is
never written to by normal package management on a quiet lab host, so any
write here is high-signal regardless of filename.

---

## 3. systemd service + timer — T1543.002

**What to look for:** process lineage showing `systemctl enable --now
system-metrics-agent.timer` (and the preceding `daemon-reload`) immediately
after new unit files appear under `/etc/systemd/system/`.

**Index:** `logs-endpoint.events.process-*` — TODO: verify.

**Query (EQL — process-lineage case, per spec preference for
systemctl/useradd execution chains):**
```eql
sequence by host.ip
  [process where process.name == "systemctl" and process.args : "daemon-reload"]
  [process where process.name == "systemctl" and process.args : "enable" and process.command_line : "*system-metrics-agent*"]
```
TODO: verify `process.args` is an array field supporting `:` wildcard match
in this EQL mapping (vs needing `process.command_line` string match only),
and verify `sequence by host.ip` is the correct correlation key vs
`process.entity_id`/`host.id`.

**Companion file check (DSL):**
```json
{
  "query": {
    "bool": {
      "filter": [
        { "wildcard": { "file.path": "/etc/systemd/system/system-metrics-agent.*" } }
      ]
    }
  }
}
```

**Key field:** `process.args` (for the EQL sequence) — the unit *files*
alone don't prove the service was ever loaded/started; the `systemctl
enable --now` invocation is what proves persistence was actually activated,
not just staged.

---

## 4. SSH authorized_keys implant — T1098.004

**What to look for:** a write to `/root/.ssh/authorized_keys` that adds the
line tagged with comment `dc862-demo-implant`.

**Index:** `logs-endpoint.events.file-*` — TODO: verify; CLAUDE.md's auditd
watch list explicitly includes `~/.ssh/authorized_keys`, so `logs-auditd*-*`
is an equally likely real source — check both.

**Query (DSL — pure file-write case):**
```json
{
  "query": {
    "bool": {
      "filter": [
        { "wildcard": { "file.path": "*/.ssh/authorized_keys" } },
        { "terms": { "event.action": ["modification", "creation", "change"] } }
      ]
    }
  }
}
```
TODO: verify whether `user.name` / `user.effective.name` is populated on
these file events so the query can be scoped to `root` specifically instead
of matching any user's authorized_keys.

**Key field:** `file.path` matched on `*/.ssh/authorized_keys` — SSH key
files change rarely on a lab host with no legitimate key-rotation activity,
so any write is a strong signal; the `dc862-demo-implant` comment string is
the confirmatory detail if file content is searchable, but path alone is
the reliable hinge field.

---

## 5. Backdoor user + sudoers entry — T1136.001

**What to look for:** process lineage of `useradd` creating user `labsvc`,
followed by a write to `/etc/sudoers.d/90-labsvc` granting
`NOPASSWD:ALL`.

**Index:** `logs-endpoint.events.process-*` — TODO: verify.

**Query (EQL — process-lineage case, per spec preference for
systemctl/useradd execution chains):**
```eql
process where process.name in ("useradd", "adduser") and process.args : "labsvc"
```
TODO: verify `process.args` array-match syntax works as written above vs
requiring `process.command_line : "*labsvc*"` instead; confirm whether
`useradd` on this distro's Elastic Defend integration reports args as a
list including the username or only the flags.

**Companion file check (DSL) — sudoers write:**
```json
{
  "query": {
    "bool": {
      "filter": [
        { "wildcard": { "file.path": "/etc/sudoers.d/90-labsvc" } },
        { "term": { "event.action": "creation" } }
      ]
    }
  }
}
```
TODO: verify `/etc/sudoers.d/` is watched by the same FIM/auditd rule set
as the other paths in CLAUDE.md's watch list — it is not explicitly listed
there (`/etc/sudoers.d` vs the listed `/etc/sudoers`), confirm coverage
before relying on this at demo time.

**Key field:** `process.args` (for the `useradd` EQL) — the sudoers file
write alone doesn't tell you who was granted access; correlating the
process execution to the literal username `labsvc` is what proves this is
the specific backdoor account from the run, not an unrelated admin task.

---

## Cross-cutting TODOs (verify against live cluster before demo)

- Confirm which of `logs-endpoint.events.file-*`, `logs-endpoint.events.process-*`,
  `logs-endpoint.events.network-*`, `logs-auditd*-*` actually exist as data
  streams on this cluster (`list_indices` MCP tool or SOC Hunt index
  pattern list) — some or all of CLAUDE.md's candidates may not be present
  depending on how Elastic Defend / auditd were finally wired up.
- Confirm `event.action` vocabulary per integration (Elastic Defend vs
  auditd emit different action strings for the same OS-level event).
- Confirm whether `process.args` is queryable as an array or only via
  `process.command_line` string matching in this EQL mapping.
- Confirm `host.ip` (10.0.2.30) is the correct scoping field vs `host.name`
  / `agent.id` for narrowing all queries to the victim VM specifically.

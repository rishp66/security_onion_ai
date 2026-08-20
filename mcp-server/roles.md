# mcp_readonly — Elasticsearch role/user for the MCP server

Backs `ES_USER=mcp_readonly` / `ES_PASSWORD` in `.env.example`. This is
guardrail 1 (read-only ES user) from `server.py`'s docstring. Do **not** use
the built-in `elastic`/admin account for the MCP server.

> **Unconfirmed index patterns.** The index patterns below are copied
> verbatim from `ALLOWED_INDEX_PATTERNS` in `server.py`
> (`logs-endpoint.events.process-*`, `logs-endpoint.events.file-*`,
> `logs-endpoint.events.network-*`, `logs-auditd*-*`). Per CLAUDE.md these are
> best-guess ECS/SO conventions, **not confirmed against the live cluster**.
> Before creating this role on the real box: run `list_indices` (or check
> Hunt/Kibana in the SOC console) to get real index/data-stream names, and
> update both this file and `server.py` together so they stay in sync.

---

## 1. Role definition (ES Security API)

Grants `read` + `view_index_metadata` only — no `write`, `create_index`,
`delete`, `manage`, or cluster privileges. Scoped to exactly the four
allowlisted patterns.

```json
{
  "cluster": [],
  "indices": [
    {
      "names": [
        "logs-endpoint.events.process-*",
        "logs-endpoint.events.file-*",
        "logs-endpoint.events.network-*",
        "logs-auditd*-*"
      ],
      "privileges": ["read", "view_index_metadata"],
      "allow_restricted_indices": false
    }
  ],
  "applications": [],
  "run_as": [],
  "metadata": {
    "description": "Read-only role for the DC862 persistence-detection MCP server. No write/manage privileges. Index patterns copied from server.py ALLOWED_INDEX_PATTERNS - unconfirmed against live cluster, verify before use."
  }
}
```

Create it directly against the ES Security API (works regardless of what SO's
CLI exposes):

```bash
curl -sk -u elastic:<ELASTIC_PASSWORD> \
  -X POST "https://10.0.1.10:9200/_security/role/mcp_readonly_role" \
  -H "Content-Type: application/json" \
  -d @role_mcp_readonly.json
```

(Save the JSON block above as `role_mcp_readonly.json` locally — do not
commit it with a real password anywhere; the role definition itself has no
secrets, only the curl command's `-u` flag does.)

---

## 2. Creating the role + user on Security Onion 2.4.201

**Needs confirmation on the live box** — SO 2.4's `so-user` CLI is documented
for managing SOC/Kibana-space users backed by SO's own auth (`so-user add`,
`so-user delete`, etc.), and it is **not confirmed** whether it can create a
custom ES *role* like the one above, or only assign existing built-in roles
to a user. Do not assume `so-user` supports custom role assignment without
checking `so-user --help` / `sudo so-user add --help` on the manager first.

Two paths, in preference order:

### Path A — `so-user`, if it supports custom roles (check first)
```bash
sudo so-user --help
sudo so-user add mcp_readonly   # interactive; sets ES-backed password
# If so-user exposes a --role or similar flag, bind it to mcp_readonly_role
# here. If not, so-user likely only offers SO's built-in role tiers
# (e.g. analyst/admin) - those are broader than needed and should NOT
# be used in place of the scoped role above.
```
Flag anything version-specific you find (exact flags, whether custom ES
roles are even supported by `so-user` in 2.4.201) — this needs to be
confirmed against the actual `so-user --help` output on the manager, it is
not guessable from memory.

### Path B — raw ES Security API (works on any ES/SO version, most reliable)
1. Create the role (step 1 above).
2. Create the user and bind it to the role:

```bash
curl -sk -u elastic:<ELASTIC_PASSWORD> \
  -X POST "https://10.0.1.10:9200/_security/user/mcp_readonly" \
  -H "Content-Type: application/json" \
  -d '{
    "password": "changeme",
    "roles": ["mcp_readonly_role"],
    "full_name": "MCP server read-only user (DC862 lab)",
    "email": ""
  }'
```

Replace `"changeme"` with a real generated secret before running on the live
box — never commit the real value. Put the real value only in the local
`.env` (already gitignored via `.env.example` being the tracked template).

If SO fronts Elasticsearch with its own reverse proxy / auth layer (some SO
versions route ES access through `so-elastic-auth` or similar rather than
exposing 9200 directly with native ES security) — this also needs
confirmation on the live box, since SO 2.4's exact ES-access architecture is
version-specific and not something to guess. Check `sudo docker ps | grep -i
elast` and SO's ES config (e.g. `/opt/so/conf/elasticsearch/`) on the manager
to see whether native ES role/user creation via the Security API works as-is
or needs an SO-specific wrapper.

---

## 3. Verification (read-only check) — do NOT run, no cluster is up

Confirms the new user can read an allowlisted index but cannot write to it.
This is documentation for later, not something to execute now.

```bash
# Should succeed (read, allowlisted index)
curl -sk -u mcp_readonly:changeme \
  "https://10.0.1.10:9200/logs-endpoint.events.process-*/_search?size=1" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match_all": {}}}'

# Should fail with a 403 / security_exception (write attempt)
curl -sk -u mcp_readonly:changeme \
  -X POST "https://10.0.1.10:9200/logs-endpoint.events.process-*/_doc" \
  -H "Content-Type: application/json" \
  -d '{"test": "should be rejected"}'

# Should fail with a 403 (index outside the allowlist, e.g. a non-endpoint
# SO index such as so-logstash-* or .kibana*)
curl -sk -u mcp_readonly:changeme \
  "https://10.0.1.10:9200/.kibana/_search?size=1"
```

Expected results: first call returns hits (or an empty result set if no data
yet, but HTTP 200); second and third calls return HTTP 403 with an ES
`security_exception` body, confirming `mcp_readonly_role` grants read-only
access scoped to the allowlisted patterns and nothing else.

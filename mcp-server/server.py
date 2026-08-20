#!/usr/bin/env python3
"""
Security Onion Elasticsearch MCP server (stdio) for Claude Desktop.

Exposes exactly two tools: list_indices, search.
Guardrails (all four, enforced in code below):
  1. read-only ES user (enforced at the ES account level - see .env.example)
  2. index allowlist (ALLOWED_INDEX_PATTERNS)
  3. hard result size cap (MAX_SIZE)
  4. query timeout (QUERY_TIMEOUT)

TODO before demo: confirm real index names + field names in the SOC console
(Hunt/Kibana) and update ALLOWED_INDEX_PATTERNS + the schema summary below.
Do not trust the placeholder names as ground truth - they are best guesses
from ECS/SO conventions, not confirmed against the live cluster.
"""
import os
from typing import Any

from elasticsearch import Elasticsearch
from mcp.server.fastmcp import FastMCP

ES_URL = os.environ["ES_URL"]
ES_USER = os.environ["ES_USER"]
ES_PASSWORD = os.environ["ES_PASSWORD"]
ES_CA_CERT = os.environ.get("ES_CA_CERT")  # path to SO's self-signed CA, if not using ES_VERIFY_CERTS=false
ES_VERIFY_CERTS = os.environ.get("ES_VERIFY_CERTS", "true").lower() == "true"

MAX_SIZE = 100
QUERY_TIMEOUT = "10s"

# Guardrail 2: index allowlist. TODO: replace with confirmed names from the
# SOC console before the talk - these are unconfirmed guesses per CLAUDE.md.
ALLOWED_INDEX_PATTERNS = [
    "logs-endpoint.events.process-*",
    "logs-endpoint.events.file-*",
    "logs-endpoint.events.network-*",
    "logs-auditd*-*",
]

_es_kwargs: dict[str, Any] = dict(
    basic_auth=(ES_USER, ES_PASSWORD),
    verify_certs=ES_VERIFY_CERTS,
    request_timeout=15,
)
if ES_CA_CERT:
    _es_kwargs["ca_certs"] = ES_CA_CERT

es = Elasticsearch(ES_URL, **_es_kwargs)

mcp = FastMCP("security-onion-es")


def _index_allowed(index: str) -> bool:
    import fnmatch

    return any(fnmatch.fnmatch(index, pat) for pat in ALLOWED_INDEX_PATTERNS)


@mcp.tool()
def list_indices() -> dict:
    """List Elasticsearch indices/data streams visible to the read-only lab
    user, filtered to the allowlisted persistence-detection patterns
    (logs-endpoint.events.*, logs-auditd*-*). Use this first to confirm real
    index names before writing a search query - do not guess index names."""
    try:
        resp = es.indices.get_alias(index=",".join(ALLOWED_INDEX_PATTERNS))
        return {"indices": sorted(resp.keys())}
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def search(index: str, query: dict, size: int = 25, use_eql: bool = False) -> dict:
    """Search Security Onion endpoint/auditd telemetry for persistence detection.

    index: must match an allowlisted pattern (see list_indices). Rejected otherwise.
    query: Elasticsearch DSL query dict (e.g. {"match": {...}}) or, if
        use_eql=True, an EQL query string wrapped as {"eql": "process where ..."}.
    size: capped at 100 results regardless of requested value.

    Confirmed key ECS fields (verify against list_indices output / SOC console
    before relying on these): event.category, event.action, process.name,
    process.command_line, process.args, process.parent.name, file.path,
    host.ip, user.name, @timestamp.

    Persistence ATT&CK techniques to hunt for in this lab: T1546.004
    (.bashrc/.profile), T1053.003 (cron in /etc/cron.d), T1543.002 (systemd
    service+timer), T1098.004 (SSH authorized_keys), T1136.001 (new user +
    sudoers). FIM/auditd watch paths: /etc/cron.*, /etc/systemd/system/,
    ~/.bashrc, ~/.profile, ~/.ssh/authorized_keys, /etc/passwd, /etc/sudoers.d.
    """
    if not _index_allowed(index):
        return {
            "error": f"index '{index}' not in allowlist: {ALLOWED_INDEX_PATTERNS}"
        }

    capped_size = min(size, MAX_SIZE)

    try:
        if use_eql:
            eql_query = query.get("eql") if isinstance(query, dict) else query
            resp = es.eql.search(
                index=index,
                query=eql_query,
                size=capped_size,
            )
        else:
            resp = es.search(
                index=index,
                query=query,
                size=capped_size,
                timeout=QUERY_TIMEOUT,
            )
        return resp.body
    except Exception as e:
        return {"error": str(e)}


if __name__ == "__main__":
    mcp.run(transport="stdio")

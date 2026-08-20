# Security Onion ES MCP server

stdio MCP server for Claude Desktop. Two tools: `list_indices`, `search`.

## Setup

```bash
cd mcp-server
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in ES creds - see below
```

Create a **read-only** ES user/role on the SO manager first (guardrail 1 —
never point this at `elastic`/admin creds):

```bash
sudo so-user add mcp_readonly   # or use ES role API for a scoped read-only role
```

## Claude Desktop config

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "security-onion": {
      "command": "/absolute/path/to/mcp-server/venv/bin/python3",
      "args": ["/absolute/path/to/mcp-server/server.py"],
      "env": {
        "ES_URL": "https://10.0.1.10:9200",
        "ES_USER": "mcp_readonly",
        "ES_PASSWORD": "...",
        "ES_VERIFY_CERTS": "false"
      }
    }
  }
}
```

## Before the talk

`list_indices` and the index allowlist in `server.py` use unconfirmed
placeholder names. Run `list_indices` against the live cluster (or check
Hunt/Kibana in the SOC console) and correct `ALLOWED_INDEX_PATTERNS` +
the field summary in the `search` tool docstring before relying on it.

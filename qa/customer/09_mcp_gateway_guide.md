# 09 — MCP Gateway (AI Integration Fabric) Guide

**Product**: AI Integration Fabric (MCP Gateway)
**Audience**: Customer Platform Engineer / Developer
**API Base**: `https://api.rt19.runtimeai.io`
**MCP Gateway**: `https://api.rt19.runtimeai.io` (port 8091 internal)
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is the MCP Gateway?

The MCP Gateway is a universal integration hub using the Model Context Protocol (JSON-RPC 2.0). It routes AI agent requests to 200+ external systems through a governed, audited pipeline.

**Key Capabilities**:
- **Integration Catalog** — 490+ pre-built MCP server integrations
- **Connection Management** — Credential-secured backend connections
- **Policy Enforcement** — Guardrails on tool invocations
- **Tool Monitoring** — Real-time invocation stream
- **Circuit Breaker** — Auto-fallback on failing integrations
- **Supply Chain Security** — SBOM + CVE tracking for MCP servers
- **Multi-Region HA** — Cross-region gateway replication

---

## Setting Up MCP Gateway on rt19

### Step 1: Browse the Integration Catalog

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# List all available MCP servers in the catalog
curl -sf -b "$COOKIE" "$API/api/mcp/catalog" | jq '.servers | length'
# Expected: 490+

# Search for specific integrations
curl -sf -b "$COOKIE" "$API/api/mcp/catalog?search=okta" | jq '.servers[] | {name, description, category}'
curl -sf -b "$COOKIE" "$API/api/mcp/catalog?search=postgresql" | jq '.servers[] | {name, description}'
curl -sf -b "$COOKIE" "$API/api/mcp/catalog?search=slack" | jq '.servers[] | {name, description}'

# Filter by category
curl -sf -b "$COOKIE" "$API/api/mcp/catalog?category=identity" | jq '.servers[] | .name'
```

### Step 2: Install MCP Server Integrations

#### Okta Integration (Identity)

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/connections" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-okta",
    "server": "mcp-server-okta",
    "config": {
      "okta_domain": "acme-corp.okta.com",
      "api_token": "<okta_api_token>",
      "scopes": ["users:read", "groups:read", "apps:read"]
    },
    "enabled": true
  }'
```

#### PostgreSQL Integration (Database)

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/connections" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-analytics-db",
    "server": "mcp-server-postgresql",
    "config": {
      "host": "analytics-db.acme-corp.internal",
      "port": 5432,
      "database": "analytics",
      "user": "readonly_agent",
      "password": "<password>",
      "ssl_mode": "require",
      "max_connections": 5,
      "read_only": true
    },
    "enabled": true
  }'
```

#### Slack Integration (Notifications)

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/connections" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-slack",
    "server": "mcp-server-slack",
    "config": {
      "bot_token": "xoxb-...",
      "default_channel": "#ai-ops",
      "allowed_channels": ["#ai-ops", "#security-alerts", "#compliance"]
    },
    "enabled": true
  }'
```

### Step 3: Verify Connections

```bash
# List all active connections
curl -sf -b "$COOKIE" "$API/api/mcp/connections" | jq '.connections[] | {name, server, status, last_health_check}'

# Health check a specific connection
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/connections/<connection_id>/health" | jq .
# Expected: {"status": "healthy", "latency_ms": 45, "last_error": null}
```

### Step 4: Invoke MCP Tools

```bash
# List available tools for a connection
curl -sf -b "$COOKIE" "$API/api/mcp/connections/<connection_id>/tools" | jq '.tools[] | {name, description}'

# Invoke a tool (e.g., list Okta users)
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/invoke" \
  -H "Content-Type: application/json" \
  -d '{
    "connection_id": "<okta_connection_id>",
    "tool": "list_users",
    "params": {
      "limit": 10,
      "filter": "status eq \"ACTIVE\""
    }
  }'

# Invoke a tool (e.g., query PostgreSQL)
curl -sf -b "$COOKIE" -X POST "$API/api/mcp/invoke" \
  -H "Content-Type: application/json" \
  -d '{
    "connection_id": "<pg_connection_id>",
    "tool": "query",
    "params": {
      "sql": "SELECT agent_name, total_requests FROM agent_metrics ORDER BY total_requests DESC LIMIT 10"
    }
  }'
```

### Step 5: Set Up Tool-Level Guardrails

```bash
# Block destructive tools on the PostgreSQL connection
curl -sf -b "$COOKIE" -X PUT "$API/api/mcp/connections/<pg_connection_id>/guardrails" \
  -H "Content-Type: application/json" \
  -d '{
    "blocked_tools": ["execute_ddl", "drop_table", "truncate"],
    "require_approval_for": ["execute_dml"],
    "allowed_tools": ["query", "describe_table", "list_tables"],
    "rate_limit": {"queries_per_minute": 30}
  }'
```

### Step 6: Monitor Tool Invocations

```bash
# Real-time tool invocation stream
curl -sf -b "$COOKIE" "$API/api/mcp/invocations?limit=20" | jq '.invocations[] | {
  timestamp: .timestamp,
  connection: .connection_name,
  tool: .tool_name,
  agent: .agent_name,
  status: .status,
  latency_ms: .latency_ms
}'

# Invocation analytics
curl -sf -b "$COOKIE" "$API/api/mcp/analytics" | jq '{
  total_invocations_today: .total_today,
  success_rate: .success_rate,
  avg_latency_ms: .avg_latency,
  top_tools: .top_tools,
  top_connections: .top_connections
}'
```

---

## MCP Gateway Internal Architecture

The MCP Gateway has 50+ internal packages:

| Package | Purpose |
|---------|---------|
| `gateway` | Core routing & orchestration |
| `catalog` | MCP server catalog management |
| `credential` | Encrypted credential storage |
| `proxy` | Request proxying & transformation |
| `firewall` | Integration-level firewall |
| `guardrails` | No-code policy guardrails |
| `dlp` | Data loss prevention on tool invocations |
| `audit` | Audit logging for gateway operations |
| `health` | Health check framework |
| `circuit breaker` | Auto-fallback on failures |
| `supply chain` | SBOM + CVE tracking |
| `discovery` | Auto-discovery of MCP servers |
| `identity` | Cross-system identity mapping |
| `webhook` | Webhook event delivery |
| `notifications` | Slack, PagerDuty, Jira alerts |
| `terraform` | Terraform provider integration |
| `playground` | Interactive API playground |
| `statuspage` | Integration status dashboard |

---

## MCP Gateway Dashboard

| Panel | Shows |
|-------|-------|
| **Integration Catalog** | Browse and install MCP servers |
| **Active Connections** | Connected backends with health status |
| **Tool Invocation Stream** | Real-time feed of tool calls |
| **Health SLA** | Uptime and latency per connection |
| **Security Dashboard** | DLP events, blocked tools, supply chain alerts |

---

## FAQ

**Q: What MCP servers come pre-built?**
A: Okta, PostgreSQL, and the SDK for building custom servers are included. The catalog has 490+ entries, but most are community-contributed definitions — you'll need to deploy the actual MCP server container.

**Q: How do I build a custom MCP server?**
A: Use the TypeScript SDK at `mcp_gateway/mcp-servers/sdk/`. Define your tools, implement the handlers, and register with the gateway. See [15_sdk_cli_integration_guide.md](15_sdk_cli_integration_guide.md).

**Q: What transport protocols does the gateway support?**
A: stdio, HTTP (Server-Sent Events), and WebSocket. The gateway normalizes all transports to a unified internal format.

**Q: How does the circuit breaker work?**
A: If a connection fails 5 times in 60 seconds, the circuit breaker opens and routes requests to a fallback (or returns a cached response). It auto-resets after 30 seconds.

**Q: Can I rate-limit tool invocations per agent?**
A: Yes. Set per-agent rate limits on connections: `"rate_limit": {"per_agent_per_minute": 10}`.

**Q: How do credentials get stored?**
A: Credentials are AES-256 encrypted at rest in PostgreSQL. The encryption key is stored in the K8s secret (`rt19-app-secrets`). For production, use Azure Key Vault.

### Advanced Setup Questions

**Q: Can I deploy MCP servers inside my VPC?**
A: Yes. Deploy MCP server containers in your own K8s cluster. Configure the gateway connection to point to your internal endpoint. The gateway communicates via outbound HTTPS.

**Q: How does the marketplace seed 490+ servers?**
A: The `seed_mcp_integrations.sh` script populates the catalog with metadata for 490+ known integrations. The actual MCP server containers are not pre-deployed — they're installed on-demand.

**Q: Can the gateway federate across multiple control planes?**
A: Multi-region HA is supported via the `multiregion` package. Each region runs its own gateway instance with shared catalog and credential sync.

**Q: How do I audit tool invocations for compliance?**
A: Every tool invocation is logged to the immutable audit trail with: timestamp, agent, tool, connection, parameters (sensitive values redacted), result status, and latency.

**Q: Can I use the MCP gateway with non-AI applications?**
A: Yes. The MCP gateway is a general-purpose integration hub. Any application that speaks JSON-RPC 2.0 can connect. The MCP protocol is transport-agnostic.

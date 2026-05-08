# MCP Gateway Guide

**Product**: Model Context Protocol Governance | **Version**: 1.0.2

---

## Overview
6-layer governance pipeline for MCP (Model Context Protocol) tool invocations.

## Pipeline Layers

| Layer | Purpose |
|-------|---------|
| 1. Authentication | Verify caller identity |
| 2. Authorization (OPA) | Check policy allows the tool call |
| 3. Rate Limiting | Enforce per-tenant/per-agent limits |
| 4. Input Validation | Sanitize and validate parameters |
| 5. Tool Execution | Forward to MCP server |
| 6. Output Filtering | DLP/PII filtering on response |

## Key APIs

```bash
# Register MCP Server
curl -X POST https://<YOUR_ENDPOINT>/api/mcp/servers \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "financial-tools", "url": "https://tools.internal:8080"}'

# Register Tool
curl -X POST https://<YOUR_ENDPOINT>/api/mcp/tools \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"server_id": "<SERVER_ID>", "name": "execute-trade", "description": "Execute stock trade"}'

# Invoke Tool (with governance)
curl -X POST https://<YOUR_ENDPOINT>/api/mcp/invoke \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"server": "financial-tools", "tool": "execute-trade", "params": {"symbol": "AAPL", "qty": 100}}'

# Audit trail
curl https://<YOUR_ENDPOINT>/api/mcp/audit?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"
```

## MCP Tool Discovery Dashboard

The enterprise dashboard includes a dedicated **MCP Tool Discovery** page (v1.0.2+) for monitoring and managing MCP servers and tools:

### Server Monitoring
- **Risk Scoring**: Each MCP server is scored 0–100 based on connection health, reachability, and anomaly patterns
- **Provenance Tracking**: See which client registered each server and when
- **Real-time Connectivity Status**: "In Sync", "Stale", "No Connection", "Unknown"
- **Bundle Age Alerts**: Automatic stale bundle detection with push recommendations

### Tool Discovery
- **Anomaly Detection**: Identifies tools with unexpected patterns (removed tools, unreachable endpoints)
- **Anomaly Reasons**: Detailed explanations of why tools are flagged (e.g., "HTTP 503 Service Unavailable")
- **Total Count Accuracy**: Shows actual API-reported tool count (not limited by UI pagination)
- **Scanner History**: Complete scan run history with duration tracking and error capture

### Scheduled Scans
- **Enhanced Cron Validation**: 5-field cron expression validation with semantic bounds checking
- **Scanner Type Selection**: Choose from available scanners (HTTP, gRPC, DNS, custom)
- **Run History**: View past scans with execution times, status, and error details
- **One-Click Triggers**: Manually initiate discovery scans when needed

## On-Prem Notes
- MCP Gateway (:8091) runs as a separate pod
- MCP servers must be network-reachable from the gateway pod
- Rate limits are stored in Redis and configurable per-tenant
- Dashboard requires network access to discovery service (:8090) for server/tool inventory

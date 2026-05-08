# Discovery Scanners Guide

**Product**: AI Agent Discovery | **Version**: 1.0.2

---

## Overview
Automated detection of AI agents across enterprise networks using 12 scanner types.

## Scanner Types

| # | Scanner | Target | Detection Method |
|---|---------|--------|-----------------|
| 1 | GitHub | Repos | REST API — scan for AI dependencies |
| 2 | AWS | Cloud | Boto3 — scan Lambda, SageMaker, Bedrock |
| 3 | Azure | Cloud | Azure SDK — scan OpenAI, ML endpoints |
| 4 | GCP | Cloud | gcloud — scan Vertex AI, Cloud Functions |
| 5 | Network | LAN | TCP probes — scan for AI service ports |
| 6 | DNS | DNS | Zone transfers — find AI CNAMEs |
| 7 | Process | Host | ps/proc — find running AI processes |
| 8 | OAuth | IdP | Token introspection — find AI clients |
| 9 | VS Code | IDE | Extension scan — find AI extensions |
| 10 | Multi-Cloud | All | Aggregated multi-provider scan |
| 11 | AI Assistant | APIs | Probe common AI assistant endpoints |
| 12 | MCP | Protocol | MCP server/tool discovery |

## Trigger Scan

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/discovery/scan \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"scan_type": "network", "targets": ["10.0.0.0/24"], "depth": "deep"}'
```

## List Discovered Agents

```bash
curl https://<YOUR_ENDPOINT>/api/discovered-agents?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"
```

## Import to Registry

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/discovery/import \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"discovered_agent_id": "<ID>"}'
```

## Dashboard Monitoring (v1.0.2+)

The enterprise dashboard includes real-time monitoring dashboards for discovery operations:

### MCP Server Health Dashboard
- **Risk Scoring**: Automated risk assessment (0–100) for each MCP server based on:
  - Connection health and reachability
  - Response time performance (p50/p99 latency)
  - Anomaly pattern detection
  - Tool count consistency
- **Provenance Tracking**: Full audit trail showing:
  - Which client registered the server
  - Which machine initiated the registration
  - When the server was first seen
- **Stale Detection**: Automatic alerts when:
  - Bundle cache hasn't updated for configurable period
  - Server becomes unreachable
  - Unexpected tool removals detected
- **Anomaly Highlighting**: Visual indicators with detailed explanations for:
  - Tools with missing endpoints
  - Services returning unexpected responses
  - Network connectivity issues

### Scan Management UI
- **Scheduled Scans**: Create recurring scans with validated cron expressions
- **Scanner Selection**: Pick specific scanner type (HTTP, gRPC, DNS, Process, Cloud, etc.)
- **Run History**: Complete audit log with:
  - Scan execution times
  - Duration tracking (start → completion)
  - Tool count results
  - Error capture and troubleshooting details
- **Manual Triggers**: One-click scan initiation for immediate investigation

## On-Prem Notes
- Network scanner requires access to target subnets (configure K8s NetworkPolicy)
- Cloud scanners need credentials (AWS/Azure/GCP) stored in K8s secrets
- Process scanner requires node-level access (DaemonSet deployment)
- Dashboard queries discovery service (:8090) for real-time server/tool inventory

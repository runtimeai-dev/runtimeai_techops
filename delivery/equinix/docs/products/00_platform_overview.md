# RuntimeAI Platform Overview

**Version**: 1.0.0 | **Date**: 2026-03-27 | **Equinix Trial Delivery**

---

## What is RuntimeAI?

RuntimeAI is the **Control Plane for the Autonomous Economy** — a multi-tenant platform that governs, secures, and audits AI agents across enterprise environments.

## Platform Products (10)

| # | Product | Description |
|---|---------|-------------|
| 1 | **Agent Registry** | Centralized catalog of AI agents with lifecycle management |
| 2 | **AI Compliance Hub** | SOC 2 / ISO 27001 / GDPR / EU AI Act compliance automation |
| 3 | **AI Firewall & DLP** | Real-time traffic inspection, egress policy enforcement |
| 4 | **eSign** | Digital document signing with audit trails |
| 5 | **Kill Switch** | Emergency agent shutdown (< 50ms via Redis) |
| 6 | **FineOps** | AI cost management, budget tracking, spend alerts |
| 7 | **MCP Gateway** | Model Context Protocol governance layer |
| 8 | **Identity Fabric** | Agent identity (X.509, SPIFFE, OAuth, mTLS) |
| 9 | **Discovery Scanner** | Automated AI agent detection across networks |
| 10 | **Marketplace** | Pre-built policy packs and compliance templates |

## Architecture

- **Control Plane**: Go monolith (273 API endpoints, :8080)
- **Data Plane**: 15+ microservices (Go, Python, Envoy/Wasm)
- **Infrastructure**: PostgreSQL 16, Redis 7.2, OPA, Prometheus, Grafana
- **Security**: RLS on 115 tables, SHA-256 Merkle audit chain, mTLS

## Quick Start

```bash
# Login to Dashboard
open https://<YOUR_ENDPOINT>/ui/

# Verify platform health
curl https://<YOUR_ENDPOINT>/healthz

# Verify audit chain integrity
curl https://<YOUR_ENDPOINT>/api/audit/verify?tenant_id=<TENANT_ID> \
  -H "X-API-Key: <AUDITOR_KEY>"
```

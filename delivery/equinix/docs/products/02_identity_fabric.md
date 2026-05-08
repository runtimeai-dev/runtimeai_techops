# Identity Fabric Guide

**Product**: Agent Identity Lifecycle | **Version**: 1.0.0

---

## Overview
Identity Fabric manages the full lifecycle of agent identities: X.509 certificates (Bot CA), SPIFFE IDs, OAuth credentials, DoH-based DNS resolution, and mTLS enforcement.

## Components

| Service | Port | Purpose |
|---------|------|---------|
| Bot CA | 8104 | X.509 certificate issuance |
| Identity DNS | 8053/1053 | DoH + DNS resolution for agents |
| Auth Service | 8090 | Session/JWT management |

## Issue Agent Certificate

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/agents/<AGENT_ID>/certify \
  -H "Authorization: Bearer <TOKEN>"
# Response: {"status": "certified"}
# Certificate valid for 30 days
```

## Verify Agent Identity (DNS)

```bash
# DoH query
curl -s https://<YOUR_ENDPOINT>:8053/dns-query?name=my-agent.runtimeai.io&type=A

# Standard DNS
dig @<YOUR_ENDPOINT> -p 1053 my-agent.runtimeai.io A
```

## Configure IdP Connector

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/idp/connectors \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "Okta", "type": "oidc", "issuer": "https://myorg.okta.com", "client_id": "<CLIENT_ID>", "client_secret": "<SECRET>"}'
```

## On-Prem Notes
- Identity DNS runs within the cluster (ClusterIP) — not exposed externally by default
- For external DNS resolution, configure Ingress to forward port 8053
- Bot CA uses ephemeral in-memory CA by default; for production, mount a persistent root CA via K8s secret

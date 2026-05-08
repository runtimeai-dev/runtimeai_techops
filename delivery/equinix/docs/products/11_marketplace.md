# Agent Marketplace Guide

**Product**: Pre-Built Policy Packs & Integrations | **Version**: 1.0.0

---

## Overview
Browse and install compliance packs, policy templates, and integration modules.

## Key APIs

```bash
# List marketplace items
curl https://<YOUR_ENDPOINT>/api/marketplace/items?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Install pack
curl -X POST https://<YOUR_ENDPOINT>/api/marketplace/install \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"item_id": "soc2-compliance-pack"}'
```

## Available Packs
- **SOC 2 Type II** — compliance controls + evidence collection
- **GDPR** — data privacy policies + consent management
- **EU AI Act** — AI-specific regulatory compliance
- **NIST AI RMF** — risk management framework
- **Financial Services** — PCI DSS + SOX compliance

## On-Prem Notes
- Marketplace service (:8096) serves packs from its local catalog
- For air-gapped: all packs are bundled in the container image

# 11 — RuntimeAI Sign (eSign Service) Guide

**Product**: RuntimeAI Sign
**Audience**: Customer Legal / Operations
**API Base**: `https://api.rt19.runtimeai.io`
**eSign UI**: `https://esign.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is RuntimeAI Sign?

Electronic signatures for both humans and AI agents with cryptographic non-repudiation:

- **Agent Cryptographic Signing** — Ed25519/ECDSA signatures from AI agents
- **Human Signature Collection** — Traditional e-signature workflows
- **Document Templates** — Reusable templates with field placement
- **Identity Verification** — KBA, SMS OTP before signing
- **Bulk Send** — Send documents to hundreds of signers
- **Tamper-Evident Audit Trail** — Cryptographic proof of document integrity
- **Compliance** — ESIGN Act, eIDAS, HIPAA, SOC 2, FedRAMP

---

## Setting Up eSign on rt19

### Step 1: Create a Document Template

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Create a document template
curl -sf -b "$COOKIE" -X POST "$API/api/esign/templates" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Agent Authorization Agreement",
    "description": "Authorization for AI agent to operate on behalf of the organization",
    "fields": [
      {"name": "sponsor_signature", "type": "signature", "required": true, "page": 1, "x": 100, "y": 600},
      {"name": "sponsor_name", "type": "text", "required": true, "page": 1, "x": 100, "y": 650},
      {"name": "sponsor_date", "type": "date", "required": true, "page": 1, "x": 300, "y": 650},
      {"name": "agent_signature", "type": "agent_crypto_sig", "required": true, "page": 1, "x": 100, "y": 720},
      {"name": "agent_id", "type": "text", "auto_fill": "agent_registry_id", "page": 1, "x": 100, "y": 770}
    ]
  }'
```

### Step 2: Send Document for Signing

```bash
# Send document based on template
curl -sf -b "$COOKIE" -X POST "$API/api/esign/documents" \
  -H "Content-Type: application/json" \
  -d '{
    "template_id": "<template_id>",
    "name": "Agent Auth - Support Bot #1",
    "signers": [
      {
        "email": "alice@acme-corp.com",
        "name": "Alice Chen",
        "role": "sponsor",
        "order": 1,
        "identity_verification": "email_otp"
      },
      {
        "agent_id": "<agent_id>",
        "role": "agent",
        "order": 2,
        "signing_method": "ed25519"
      }
    ],
    "message": "Please review and sign the agent authorization agreement.",
    "expiry_days": 30
  }'
```

### Step 3: Check Document Status

```bash
# List all documents
curl -sf -b "$COOKIE" "$API/api/esign/documents" | jq '.documents[] | {
  name: .name,
  status: .status,
  signers: [.signers[] | {name: .name, signed: .signed, signed_at: .signed_at}],
  created_at: .created_at
}'

# Get specific document status
curl -sf -b "$COOKIE" "$API/api/esign/documents/<document_id>" | jq .
```

### Step 4: Agent Cryptographic Signing

When it's the agent's turn to sign, the system uses the agent's registered cryptographic key.

```bash
# Agent signs a document (typically automated via agent workflow)
curl -sf -b "$COOKIE" -X POST "$API/api/esign/documents/<document_id>/sign" \
  -H "Content-Type: application/json" \
  -d '{
    "signer_id": "<agent_signer_id>",
    "signing_method": "ed25519",
    "agent_key_id": "<agent_crypto_key_id>"
  }'
```

### Step 5: Verify Document Integrity

```bash
# Verify document has not been tampered with
curl -sf -b "$COOKIE" -X POST "$API/api/esign/documents/<document_id>/verify" | jq '{
  valid: .valid,
  signatures: [.signatures[] | {signer: .signer_name, valid: .signature_valid, algorithm: .algorithm}],
  document_hash: .document_hash,
  chain_verified: .audit_chain_verified
}'
```

### Step 6: Bulk Send

```bash
# Send same document to multiple signers
curl -sf -b "$COOKIE" -X POST "$API/api/esign/bulk-send" \
  -H "Content-Type: application/json" \
  -d '{
    "template_id": "<template_id>",
    "recipients": [
      {"email": "alice@acme-corp.com", "name": "Alice Chen"},
      {"email": "bob@acme-corp.com", "name": "Bob Smith"},
      {"email": "carol@acme-corp.com", "name": "Carol Davis"}
    ],
    "message": "Please sign the Q1 AI governance attestation.",
    "expiry_days": 14
  }'
```

---

## eSign Dashboard

Access the eSign UI at `https://esign.rt19.runtimeai.io`:

| View | Purpose |
|------|---------|
| **Documents** | All documents with status (draft, sent, signed, expired) |
| **Templates** | Reusable document templates |
| **Audit Trail** | Complete signing history with cryptographic proof |
| **Analytics** | Signing metrics (completion rate, average time to sign) |

---

## FAQ

**Q: What signing standards does eSign support?**
A: ESIGN Act (US), eIDAS (EU), and UETA. Documents include tamper-evident hashes and timestamped audit trails.

**Q: Can an AI agent sign a legally binding document?**
A: Yes, when combined with a human sponsor co-signature. The agent's cryptographic signature provides non-repudiation, while the sponsor provides legal authority.

**Q: What identity verification methods are available?**
A: Email OTP, SMS OTP, and Knowledge-Based Authentication (KBA). Configure per signer.

**Q: Can I embed signing in my own application?**
A: Yes. Use the embedded signing API to generate a signing URL that can be iframed or linked from your application.

**Q: How long are signed documents stored?**
A: Documents are stored in Azure Blob Storage. Retention is configurable per tenant (default: 7 years for compliance).

**Q: Can I decline a document?**
A: Yes. Signers can decline with a reason. The document creator is notified and can resend or cancel.

### Advanced Setup Questions

**Q: How does the eSign service scale?**
A: Target: 1M users, 5M documents/month. Database connections pool at 50 per pod. Rate limited at 100 req/min per IP. Scale horizontally by increasing replicas.

**Q: Can I use HSM for signing keys?**
A: HSM key management is supported for enterprise-grade key storage. Configure via `ESIGN_HSM_PROVIDER` env var on the esign-service deployment.

**Q: How do I set up Stripe billing for eSign?**
A: Configure `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` on the esign-service. Set up pricing plans via the SaaS Admin App. See [13_billing_saas_admin_guide.md](13_billing_saas_admin_guide.md).

**Q: Can I use eSign for cross-tenant documents?**
A: Yes. Cross-tenant document sharing is supported. The sender's tenant owns the document, and signers from other tenants receive access via email invitation.

# eSign Service Guide

**Product**: Digital Document Signing | **Version**: 1.0.0

---

## Overview
Enterprise digital document signing with multi-signer workflows, audit trails, and compliance evidence.

## Components

| Service | Port | Purpose |
|---------|------|---------|
| eSign Service | 3001 | API + signing logic |
| eSign Landing | 3002 | Signer-facing web UI |

## Key Features
- Multi-signer sequential/parallel workflows
- PDF signature watermarks with timestamps
- Completed document download with audit certificate
- Email notifications via SendGrid

## Workflow

1. **Create Package**: Upload PDF, define signers
2. **Send**: Email links sent to signers
3. **Sign**: Each signer opens link, reviews document, signs
4. **Complete**: All signatures collected → completed PDF available for download

## On-Prem Notes
- Requires SendGrid API key or SMTP relay in `rt19-email-secrets`
- For testing without email, use Mailpit (`localhost:8025`)
- Document storage: local filesystem within pod (use PersistentVolume for production)
- Signed PDFs include embedded SHA-256 audit trail in metadata

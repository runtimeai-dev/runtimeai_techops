# Scanner 05: Manual Agent Ingestion (API)
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ✅ PASS

## Setup
- **Endpoint**: `POST /v1/discovery/ingest/agent`
- **Auth**: `X-API-Key: <API_KEY_SECRET>`
- **Purpose**: Ingest agents discovered through external integrations (Zapier, Slack, etc.)

## Test: 3 Real-World Agents

### Agent 1: Ollama Local LLM
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/ingest/agent" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "equinix-test",
    "name": "Ollama Local LLM",
    "source": "process",
    "description": "Local LLM running on dev laptop",
    "capabilities": ["text-generation", "embeddings"],
    "agent_type": "local_llm",
    "environment": "development"
  }'
```
Response: `{"status":"ingested","scan_id":"82eb4dba-...","agents_processed":1}`

### Agent 2: VS Code Copilot Extension
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/ingest/agent" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "equinix-test",
    "name": "VS Code Copilot Extension",
    "source": "vscode",
    "description": "GitHub Copilot running in VS Code",
    "capabilities": ["code-completion", "chat"],
    "agent_type": "ide_extension",
    "environment": "development"
  }'
```
Response: `{"status":"ingested","scan_id":"3be7f42c-...","agents_processed":1}`

### Agent 3: Salesforce Einstein GPT
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/ingest/agent" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "equinix-test",
    "name": "Salesforce Einstein GPT",
    "source": "salesforce",
    "description": "AI assistant in Salesforce CRM",
    "capabilities": ["lead-scoring", "email-generation"],
    "agent_type": "saas_ai",
    "environment": "production"
  }'
```
Response: `{"status":"ingested","scan_id":"cfa4ed1a-...","agents_processed":1}`

## Validation
All 3 agents appear in `/v1/inventory/discovered?tenant_id=equinix-test` with:
- Fingerprints: `external:process:ollama-local-llm`, `external:vscode:vs-code-copilot-extension`, `external:salesforce:salesforce-einstein-gpt`
- All status: `UNREGISTERED` (ready for triage)

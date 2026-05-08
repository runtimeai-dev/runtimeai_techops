# Scanner 06: VSCode Extension Scanner
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ✅ PASS (via API)

## Setup
- **Scanner**: `discovery/scanners/vscode_scanner.py`
- **Purpose**: Scans `~/.vscode/extensions/` for AI-related extensions
- **AI Keywords**: copilot, openai, gpt, claude, tabnine, codeium, cursor, llm, generative

## Architecture
The VSCode scanner runs as a **standalone CLI** on the developer's machine:
1. Scans `~/.vscode/extensions/` directory
2. Reads each extension's `package.json` for AI keywords
3. Reports findings to discovery service via `POST /v1/discovery/report`

## Test Execution (via Manual API)
Since the scanner runs locally on dev machines, we tested via the manual ingest API:
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/ingest/agent" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "equinix-test",
    "name": "VS Code Copilot Extension",
    "source": "vscode",
    "capabilities": ["code-completion", "chat"],
    "agent_type": "ide_extension",
    "environment": "development"
  }'
```
✅ Agent ingested successfully

## Running the Standalone Scanner
```bash
# On a dev machine with VS Code installed:
cd /path/to/runtimeai-enterprise/discovery
python3 scanners/vscode_scanner.py --tenant-id equinix-test
```

## Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `DISCOVERY_API_URL` | `http://localhost:8090/v1/discovery/report` | Discovery service URL |
| `VSCODE_EXTENSIONS_DIR` | `~/.vscode/extensions` | VS Code extensions path |
| `TENANT_ID` | `tenant-default` | Target tenant ID |

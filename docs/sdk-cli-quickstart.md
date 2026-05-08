# RuntimeAI SDK & CLI Quick Start

## Installation

### TypeScript SDK

```bash
npm install @runtimeai/sdk
```

```typescript
import { RuntimeAI } from '@runtimeai/sdk';

const client = new RuntimeAI({
  apiUrl: 'https://api.your-pod.runtimeai.io',
  apiKey: process.env.RUNTIMEAI_API_KEY!,
});

// Register an agent
const agent = await client.agents.register({
  name: 'contract-analyzer',
  type: 'langchain',
  owner: 'ml-team@company.com',
});
```

### Python SDK

```bash
pip install runtimeai
```

```python
from runtimeai import RuntimeAI

client = RuntimeAI(
    "https://api.your-pod.runtimeai.io",
    api_key="your-api-key",
)

# Register an agent
agent = client.agents.register(
    name="contract-analyzer",
    type="langchain",
    owner="ml-team@company.com",
)
```

### CLI

```bash
# macOS (Homebrew)
brew install runtimeai-dev/tap/runtimeai-cli

# Linux / Windows — download from GitHub Releases
# https://github.com/runtimeai-dev/runtimeai-enterprise/releases

# Configure
runtimeai-cli config set --api-url https://api.your-pod.runtimeai.io --api-key YOUR_KEY

# Verify
runtimeai-cli health
runtimeai-cli agents list
```

## Authentication

All SDKs and the CLI support two authentication methods:

| Method | Header | SDK Param | CLI Flag |
|--------|--------|-----------|----------|
| API Key | `X-API-Key` | `apiKey` / `api_key` | `--api-key` |
| JWT Token | `Authorization: Bearer` | `authToken` / `auth_token` | (via config) |

## Available Operations

| Domain | SDK Method (TS) | SDK Method (Python) | CLI Command |
|--------|----------------|--------------------|----|
| **Agents** | `client.agents.register()` | `client.agents.register()` | `runtimeai-cli agents list` |
| **Discovery** | `client.discovery.listFindings()` | `client.discovery.list_findings()` | `runtimeai-cli discovery findings` |
| **FinOps** | `client.finops.reportUsage()` | `client.finops.report_usage()` | `runtimeai-cli finops usage` |
| **Policies** | `client.policies.listGuardrails()` | `client.policies.list_guardrails()` | `runtimeai-cli policies list` |
| **MCP** | `client.mcp.listTools()` | `client.mcp.list_tools()` | — |
| **Compliance** | `client.compliance.listFrameworks()` | `client.compliance.list_frameworks()` | — |
| **Audit** | `client.audit.list()` | `client.audit.list()` | — |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `RUNTIMEAI_API_URL` | Control Plane API URL |
| `RUNTIMEAI_API_KEY` | API key for authentication |
| `RUNTIMEAI_TENANT_ID` | Tenant ID for multi-tenant operations |

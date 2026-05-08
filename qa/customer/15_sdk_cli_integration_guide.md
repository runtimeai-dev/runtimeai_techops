# 15 — SDK & CLI Integration Guide

**Product**: RuntimeAI SDK & CLI
**Audience**: Customer Developer / DevOps
**API Base**: `https://api.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Are the SDK & CLI?

Developer tools for integrating AI agents with the RuntimeAI platform:

- **SDK** — TypeScript/Go libraries for agent registration, MCP server building, and policy integration
- **CLI** — Command-line tool for managing agents, running scans, and deploying policies
- **MCP Server SDK** — Build custom MCP server integrations

---

## SDK Setup

### TypeScript SDK

```bash
# Install the RuntimeAI SDK
npm install @runtimeai/sdk

# Or from the repository
cd /Users/roshanshaik/work/runtimeai-enterprise/sdk
npm install && npm run build
```

```typescript
import { RuntimeAI } from '@runtimeai/sdk';

const client = new RuntimeAI({
  apiUrl: 'https://api.rt19.runtimeai.io',
  apiKey: '<your_api_key>',
  tenantId: 'acme-corp'
});

// Register an agent
const agent = await client.agents.register({
  name: 'my-analytics-bot',
  type: 'data_analyst',
  model: 'gpt-4o',
  blueprintId: '<blueprint_id>'
});

// Report cost event
await client.finops.reportUsage({
  agentId: agent.id,
  provider: 'openai',
  model: 'gpt-4o',
  inputTokens: 1500,
  outputTokens: 800
});

// Check agent trust score
const trustScore = await client.agents.getTrustScore(agent.id);
console.log(`Trust Score: ${trustScore.score}/100`);
```

### Go SDK

```go
import "github.com/runtimeai-dev/runtimeai/sdk"

client, err := sdk.NewClient(sdk.Config{
    APIURL:   "https://api.rt19.runtimeai.io",
    APIKey:   "<your_api_key>",
    TenantID: "acme-corp",
})

// Register agent
agent, err := client.Agents.Register(ctx, &sdk.AgentInput{
    Name:  "my-bot",
    Type:  "chatbot",
    Model: "gpt-4o",
})

// Report cost
err = client.FinOps.ReportUsage(ctx, &sdk.CostEvent{
    AgentID:      agent.ID,
    Provider:     "openai",
    Model:        "gpt-4o",
    InputTokens:  1500,
    OutputTokens: 800,
})
```

---

## MCP Server SDK

Build custom MCP server integrations using the TypeScript SDK.

```bash
cd /Users/roshanshaik/work/runtimeai/mcp_gateway/mcp-servers/sdk
npm install
```

```typescript
import { MCPServer, Tool, ToolResult } from '@runtimeai/mcp-sdk';

const server = new MCPServer({
  name: 'my-custom-integration',
  version: '1.0.0',
  description: 'Custom integration for Acme internal systems'
});

// Define tools
server.addTool(new Tool({
  name: 'get_customer',
  description: 'Look up a customer by ID',
  parameters: {
    type: 'object',
    properties: {
      customer_id: { type: 'string', description: 'Customer ID' }
    },
    required: ['customer_id']
  },
  handler: async (params): Promise<ToolResult> => {
    const customer = await lookupCustomer(params.customer_id);
    return { content: JSON.stringify(customer) };
  }
}));

// Start the server (stdio or HTTP)
server.start({ transport: 'http', port: 8100 });
```

### Register Custom MCP Server with Gateway

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

curl -sf -b "$COOKIE" -X POST "$API/api/mcp/connections" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-custom-integration",
    "server": "custom",
    "config": {
      "url": "http://my-custom-mcp:8100",
      "transport": "http",
      "auth": {
        "type": "bearer",
        "token": "<service_token>"
      }
    },
    "enabled": true
  }'
```

---

## CLI Tool

### Installation

```bash
# Install CLI
cd /Users/roshanshaik/work/runtimeai-enterprise/cli
go install ./cmd/runtimeai-cli

# Or download pre-built binary (when available)
# curl -sSL https://get.runtimeai.io/cli | bash
```

### Configuration

```bash
# Configure CLI
runtimeai-cli config set --api-url https://api.rt19.runtimeai.io
runtimeai-cli config set --api-key <your_api_key>
runtimeai-cli config set --tenant-id acme-corp

# Verify connection
runtimeai-cli health
```

### Common CLI Commands

```bash
# Agent management
runtimeai-cli agents list
runtimeai-cli agents get <agent_id>
runtimeai-cli agents register --name my-bot --type chatbot --model gpt-4o
runtimeai-cli agents kill-switch <agent_id> --reason "investigation"

# Discovery
runtimeai-cli discovery scan --type cloud --provider aws
runtimeai-cli discovery findings --status shadow

# Compliance
runtimeai-cli compliance posture
runtimeai-cli compliance gaps --framework soc2

# FinOps
runtimeai-cli finops summary
runtimeai-cli finops budgets list

# MCP Gateway
runtimeai-cli mcp catalog search "okta"
runtimeai-cli mcp connections list
runtimeai-cli mcp invoke <connection_id> <tool_name> --params '{"key": "value"}'
```

---

## API Authentication

### API Key Authentication

```bash
# Generate API key via dashboard: Settings → API Keys → Generate
# Use in requests:
curl -sf -X GET "$API/api/agents" \
  -H "Authorization: Bearer <api_key>" \
  -H "X-Tenant-ID: acme-corp"
```

### Session Cookie Authentication

```bash
# Login to get session cookie
curl -sf -c /tmp/session.txt -X POST "$API/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "acme-corp", "email": "dev@acme-corp.com", "password": "..."}'

# Use session cookie
curl -sf -b /tmp/session.txt "$API/api/agents"
```

### OAuth2 Client Credentials (Agent Authentication)

```bash
# Agent authenticates with client credentials
TOKEN=$(curl -sf -X POST "$API/api/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=<agent_client_id>&client_secret=<agent_client_secret>" \
  | jq -r '.access_token')

# Use JWT token
curl -sf -X GET "$API/api/agents/me" \
  -H "Authorization: Bearer $TOKEN"
```

---

## FAQ

**Q: Is the SDK published to npm/Go modules?**
A: Not yet. The SDK is currently source-distributed. npm/Go module publishing is on the roadmap. See [gaps_issues.md](gaps_issues.md).

**Q: Is the CLI published as a binary?**
A: Not yet. You need to build from source. Pre-built binaries for macOS/Linux/Windows are on the roadmap.

**Q: Can I use the REST API directly without the SDK?**
A: Yes. All SDK operations are thin wrappers around the REST API. You can use `curl` or any HTTP client.

**Q: What authentication method should I use for automated pipelines?**
A: API key authentication for CI/CD pipelines. OAuth2 client credentials for agent-to-API communication.

**Q: Can I use the SDK from Python?**
A: No Python SDK yet. Use the REST API directly with `requests` or `httpx`. Python SDK is on the roadmap.

### Advanced Setup Questions

**Q: How do I publish a custom MCP server to GHCR?**
A: Build the Docker image, push to GHCR: `docker push ghcr.io/runtimeai-dev/<server-name>:latest`. Then register in the MCP catalog. Note: Agent registration SDK images are not yet published to GHCR — see [gaps_issues.md](gaps_issues.md).

**Q: Can I integrate the SDK into my CI/CD pipeline for agent deployment?**
A: Yes. Use the Go CLI or SDK in your CI/CD pipeline to: 1) Register agents on deploy 2) Update blueprints 3) Rotate credentials 4) Run compliance checks.

**Q: How do I handle SDK version upgrades?**
A: The SDK follows semantic versioning. Pull the latest from the repository. Breaking changes are documented in release notes.

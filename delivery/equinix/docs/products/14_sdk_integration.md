# RuntimeAI SDK Integration Guide (Source-Bundled Edition)

**Version**: 1.0.0-equinix
**Date**: 2026-03-28

---

## Executive Summary

For air-gapped and highly secure environments like Equinix, the RuntimeAI SDKs are not fetched from public registries (PyPI, npm). Instead, we utilize a **Source-Bundled SDK Strategy**.

The complete source code for both the Python and TypeScript SDKs is included directly within your delivery package:
- `sdk-python/` — The complete Python SDK source and package definitions.
- `sdk-typescript/` — The complete TypeScript/Node SDK source and package definitions.

This guarantees that:
1. No outbound internet access is required to install dependencies.
2. The exact SDK version tested with your platform deployment is the one you integrate.
3. Your security team can perform full static analysis on the SDK source code before deployment.

---

## 1. Python SDK Installation

To install the Python SDK in your local or CI/CD environment directly from the delivery bundle:

```bash
# Navigate to the Python SDK directory within the delivery package
cd path/to/delivery/sdk-python

# Install the SDK from the local directory (editable mode recommended for local dev)
pip install -e .

# Or build and install a wheel
python -m build
pip install dist/runtimeai-1.0.0-py3-none-any.whl
```

### Basic Python Usage

```python
import os
from runtimeai import RuntimeAIClient

# Initialize the client using your provided admin secret and on-prem API URL
client = RuntimeAIClient(
    api_key=os.getenv("RTAI_API_KEY"),
    base_url="https://api.rt19.equinix-internal.local"
)

# 1. Register a new Agent
agent = client.agents.create(
    name="finance-processor-v2",
    description="Handles internal finance routing",
    owner="finops-team",
    risk_tier="critical",
    capabilities=["payment_processing"]
)
print(f"Registered Agent ID: {agent.id}")

# 2. Check an Egress Policy
decision = client.policies.check_egress(
    destination="api.openai.com",
    agent_id=agent.id
)
if decision.action == "block":
    print("WARNING: Egress blocked by RuntimeAI policy.")

# 3. Activate Kill Switch in anomalies
client.kill_switch.activate(
    target=agent.id,
    scope="agent",
    reason="Anomalous behavior detected",
    duration="1h"
)
```

---

## 2. TypeScript SDK Installation

To install the TypeScript SDK directly from the delivery bundle:

```bash
# Navigate to the TypeScript SDK directory
cd path/to/delivery/sdk-typescript

# Build the SDK locally
npm install
npm run build

# Link the local SDK to your application project
npm link

# In your application directory:
npm link @runtimeai/sdk
```

Alternatively, you can package the SDK and install the tarball directly:

```bash
# Inside sdk-typescript/
npm pack

# In your application directory:
npm install ../path/to/delivery/sdk-typescript/runtimeai-sdk-1.0.0.tgz
```

### Basic TypeScript Usage

```typescript
import { RuntimeAIClient } from '@runtimeai/sdk';

const client = new RuntimeAIClient({
  apiKey: process.env.RTAI_API_KEY,
  baseUrl: "https://api.rt19.equinix-internal.local"
});

async function runGovernancePipeline() {
  // 1. Fetch available MCP tools
  const tools = await client.mcp.listTools();
  console.log(`Found ${tools.length} governed tools.`);

  // 2. Invoke a tool via the Gateway
  try {
    const response = await client.mcp.invoke({
      serverId: "okta-server",
      toolName: "list_users",
      agentId: "my-internal-agent"
    });
    console.log("Gov-checked invocation success:", response.data);
  } catch (err) {
    if (err.code === "POLICY_VIOLATION") {
      console.error("Action blocked by governance policies:", err.message);
    }
  }
}

runGovernancePipeline();
```

---

## Advanced: CI/CD Pipeline Integration

When integrating the bundled SDK into your CI/CD pipelines (e.g., GitLab CI on-prem or Jenkins):

1. **Option 1: Include in Repository**: Commit the `sdk-python` or `sdk-typescript` folder directly into a monorepo or vendor directory.
2. **Option 2: Internal Registry Publish**: Use the bundled source to publish to your organization's internal, air-gapped registry (e.g., Artifactory, Nexus).

**Example for Internal PyPI (Artifactory):**
```bash
cd sdk-python
python -m build
twine upload --repository-url https://artifactory.internal/api/pypi/local dist/*
```

**Example for Internal npm (Nexus):**
```bash
cd sdk-typescript
npm publish --registry=https://nexus.internal/repository/npm-hosted/
```

This guarantees zero public internet reliance while enabling your internal developer platform to consume the packages naturally.

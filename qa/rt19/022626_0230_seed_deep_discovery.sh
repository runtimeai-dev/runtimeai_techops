#!/bin/bash
# Seed data for IF-DSC-005 through IF-DSC-011 deep discovery features
# Created: 022626_0230 | Updated: 022626_1045
# Seeds both discovered_agents (IF-DSC-005..010) and MCP tables (IF-DSC-011) via API

set -e

BASE_URL="http://localhost:4000/api"
COOKIE_FILE="/tmp/discovery_deep_session.txt"

echo "=== IF-DSC Deep Features Seed Data ==="

# 1. Login
echo "Logging in..."
curl -s -c "$COOKIE_FILE" -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"a-operator@bank-a.local","password":"password123"}' | head -c 200
echo ""

TENANT_ID="tenant-bank-a"

# 2. Seed Cloud Scanner Results (IF-DSC-005) — via discovered_agents
echo "Seeding cloud scanner discoveries..."
for i in 1 2 3; do
curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d "{
    \"source\": \"aws\",
    \"agents\": [
      {\"name\": \"aws-lambda-langchain-processor-$i\", \"source_scanner\": \"aws\", \"risk_score\": $((3 + i)),
       \"metadata\": {\"resource_type\": \"lambda\", \"region\": \"us-east-1\", \"ai_framework\": \"langchain\"}},
      {\"name\": \"aws-sagemaker-endpoint-$i\", \"source_scanner\": \"aws\", \"risk_score\": $((2 + i)),
       \"metadata\": {\"resource_type\": \"sagemaker\", \"region\": \"us-west-2\", \"ai_framework\": \"pytorch\"}}
    ]
  }" > /dev/null 2>&1
done

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "azure",
    "agents": [
      {"name": "azure-func-openai-handler", "source_scanner": "azure", "risk_score": 5,
       "metadata": {"resource_type": "function", "region": "eastus", "ai_framework": "openai"}},
      {"name": "azure-ai-studio-agent-copilot", "source_scanner": "azure", "risk_score": 6,
       "metadata": {"resource_type": "ai_studio", "region": "westeurope", "ai_framework": "semantic-kernel"}}
    ]
  }' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "gcp",
    "agents": [
      {"name": "gcp-vertex-ai-agent-v2", "source_scanner": "gcp", "risk_score": 4,
       "metadata": {"resource_type": "vertex_ai", "region": "us-central1", "ai_framework": "gemini"}},
      {"name": "gcp-cloud-function-crewai", "source_scanner": "gcp", "risk_score": 7,
       "metadata": {"resource_type": "cloud_function", "region": "europe-west1", "ai_framework": "crewai"}}
    ]
  }' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "kubernetes",
    "agents": [
      {"name": "k8s-pod-langchain-worker", "source_scanner": "kubernetes", "risk_score": 5,
       "metadata": {"resource_type": "pod", "region": "production-cluster", "ai_framework": "langchain"}},
      {"name": "k8s-deployment-ray-serve", "source_scanner": "kubernetes", "risk_score": 3,
       "metadata": {"resource_type": "deployment", "region": "staging-cluster", "ai_framework": "ray"}}
    ]
  }' > /dev/null 2>&1
echo "  ✓ Cloud scanner discoveries seeded (12 agents)"

# 3. Seed IDE Scanner Results (IF-DSC-006)
echo "Seeding IDE scanner discoveries..."
curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "vscode",
    "agents": [
      {"name": "GitHub Copilot Extension", "source_scanner": "vscode", "risk_score": 2,
       "metadata": {"extension_id": "GitHub.copilot", "mcp_configs": 0, "api_key_present": false}},
      {"name": "Continue Extension (BYO Key)", "source_scanner": "vscode", "risk_score": 7,
       "metadata": {"extension_id": "Continue.continue", "mcp_configs": 3, "api_key_present": true}},
      {"name": "Cursor MCP Config", "source_scanner": "cursor", "risk_score": 5,
       "metadata": {"extension_id": "cursor.mcp", "mcp_configs": 5, "api_key_present": false}},
      {"name": "aider CLI Tool", "source_scanner": "cli_tools", "risk_score": 8,
       "metadata": {"extension_id": "aider", "mcp_configs": 0, "api_key_present": true}}
    ]
  }' > /dev/null 2>&1
echo "  ✓ IDE scanner discoveries seeded (4 detections)"

# 4. Seed Endpoint Results (IF-DSC-007)
echo "Seeding endpoint discoveries..."
curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "endpoint",
    "agents": [
      {"name": "python3 langchain-agent.py", "source_scanner": "process", "risk_score": 6,
       "metadata": {"hostname": "dev-laptop-01", "os": "macOS", "ai_processes": 3}},
      {"name": "docker: crewai-multi-agent", "source_scanner": "process", "risk_score": 7,
       "metadata": {"hostname": "build-server-02", "os": "Ubuntu 22.04", "ai_processes": 5}},
      {"name": "ollama serve (llama3)", "source_scanner": "endpoint", "risk_score": 4,
       "metadata": {"hostname": "ml-workstation-03", "os": "Ubuntu 24.04", "ai_processes": 1}}
    ]
  }' > /dev/null 2>&1
echo "  ✓ Endpoint discoveries seeded (3 machines)"

# 5. Seed Automation Results (IF-DSC-008)
echo "Seeding automation discoveries..."
curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "automation",
    "agents": [
      {"name": "cron: daily-langchain-etl.py", "source_scanner": "cron", "risk_score": 6,
       "metadata": {"schedule": "0 2 * * *", "command": "python3 /opt/ai/langchain-etl.py", "ai_framework": "langchain"}},
      {"name": "systemd: ai-chatbot.service", "source_scanner": "systemd", "risk_score": 5,
       "metadata": {"schedule": "always", "command": "ExecStart=/usr/bin/python3 chatbot.py", "ai_framework": "openai"}},
      {"name": "github-actions: ai-review.yml", "source_scanner": "github", "risk_score": 4,
       "metadata": {"schedule": "on: pull_request", "command": "openai/chat-completion@v1", "ai_framework": "openai"}},
      {"name": "lambda: scheduled-bedrock-sync", "source_scanner": "lambda", "risk_score": 3,
       "metadata": {"schedule": "rate(1 hour)", "command": "bedrock-sync-handler", "ai_framework": "bedrock"}}
    ]
  }' > /dev/null 2>&1
echo "  ✓ Automation discoveries seeded (4 tasks)"

# 6. Seed AI Assistant Results (IF-DSC-010)
echo "Seeding AI assistant discoveries..."
curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/import" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "ai_assistant",
    "agents": [
      {"name": "GitHub Copilot", "source_scanner": "ai_assistant", "risk_score": 2,
       "metadata": {"risk_tier": "LOW", "vendor": "GitHub", "tool_category": "ide_extension", "mcp_servers_count": 0, "api_key_present": false, "machine": "dev-laptop-01"}},
      {"name": "Cursor IDE", "source_scanner": "ai_assistant", "risk_score": 5,
       "metadata": {"risk_tier": "MEDIUM", "vendor": "Anysphere", "tool_category": "ai_ide", "mcp_servers_count": 4, "api_key_present": false, "machine": "dev-laptop-02"}},
      {"name": "Claude Code CLI", "source_scanner": "ai_assistant", "risk_score": 5,
       "metadata": {"risk_tier": "MEDIUM", "vendor": "Anthropic", "tool_category": "terminal_agent", "mcp_servers_count": 7, "api_key_present": true, "machine": "dev-laptop-01"}},
      {"name": "aider", "source_scanner": "ai_assistant", "risk_score": 8,
       "metadata": {"risk_tier": "HIGH", "vendor": "OSS", "tool_category": "terminal_agent", "mcp_servers_count": 0, "api_key_present": true, "machine": "dev-laptop-03"}},
      {"name": "Claude Desktop", "source_scanner": "desktop_ai", "risk_score": 7,
       "metadata": {"risk_tier": "HIGH", "vendor": "Anthropic", "tool_category": "desktop_app", "mcp_servers_count": 12, "api_key_present": false, "machine": "dev-laptop-01"}},
      {"name": "Ollama", "source_scanner": "local_llm", "risk_score": 4,
       "metadata": {"risk_tier": "MEDIUM", "vendor": "Ollama", "tool_category": "local_llm", "mcp_servers_count": 0, "api_key_present": false, "machine": "ml-workstation-03"}},
      {"name": "AutoGPT", "source_scanner": "ai_assistant", "risk_score": 9,
       "metadata": {"risk_tier": "CRITICAL", "vendor": "Significant Gravitas", "tool_category": "autonomous_agent", "mcp_servers_count": 0, "api_key_present": true, "machine": "dev-laptop-04"}},
      {"name": "Bolt.new", "source_scanner": "cloud_platform", "risk_score": 7,
       "metadata": {"risk_tier": "HIGH", "vendor": "StackBlitz", "tool_category": "cloud_platform", "mcp_servers_count": 0, "api_key_present": false, "machine": "browser"}}
    ]
  }' > /dev/null 2>&1
echo "  ✓ AI assistant discoveries seeded (8 tools)"

# 7. Seed MCP Servers (IF-DSC-011) — via POST /api/discovery/mcp/servers
echo "Seeding MCP servers..."

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server-filesystem","transport":"stdio","command":"npx -y @modelcontextprotocol/server-filesystem","source_client":"claude_desktop","source_machine":"dev-laptop-01","env_vars_passed":["HOME"],"risk_score":6,"tools_count":6}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server-postgres","transport":"stdio","command":"npx -y @modelcontextprotocol/server-postgres","source_client":"cursor","source_machine":"dev-laptop-02","env_vars_passed":["DATABASE_URL"],"risk_score":7,"tools_count":4}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server-github","transport":"stdio","command":"npx -y @modelcontextprotocol/server-github","source_client":"claude_desktop","source_machine":"dev-laptop-01","env_vars_passed":["GITHUB_TOKEN"],"risk_score":5,"tools_count":12}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"custom-internal-api","transport":"sse","url":"https://internal-mcp.corp.example.com/sse","source_client":"vscode","source_machine":"dev-laptop-03","env_vars_passed":["API_KEY","API_SECRET"],"risk_score":8,"tools_count":8}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"mcp-server-slack","transport":"http","url":"https://mcp-slack.example.com/mcp","source_client":"windsurf","source_machine":"dev-laptop-02","env_vars_passed":["SLACK_TOKEN"],"risk_score":4,"tools_count":5}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/servers" \
  -H "Content-Type: application/json" \
  -d '{"name":"rogue-shell-server","transport":"stdio","command":"python3 /tmp/shell_server.py","source_client":"cursor","source_machine":"dev-laptop-04","env_vars_passed":[],"risk_score":10,"tools_count":3}' > /dev/null 2>&1

echo "  ✓ MCP servers seeded (6 servers via API)"

# 8. Seed MCP Policies (IF-DSC-011) — via POST /api/discovery/mcp/policies
echo "Seeding MCP policies..."

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"block_tool","pattern":"shell_execute"}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"block_server","pattern":"rogue-*"}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"allow_server","pattern":"mcp-server-*"}' > /dev/null 2>&1

curl -s -b "$COOKIE_FILE" -X POST "$BASE_URL/discovery/mcp/policies" \
  -H "Content-Type: application/json" \
  -d '{"policy_type":"require_approval","pattern":"custom-*"}' > /dev/null 2>&1

echo "  ✓ MCP policies seeded (4 policies via API)"

echo ""
echo "=== Seed Complete ==="
echo "Cloud scanners: 12 agents (AWS, Azure, GCP, K8s)"
echo "IDE scanners: 4 detections"
echo "Endpoints: 3 machines"
echo "Automations: 4 tasks"
echo "AI Assistants: 8 tools across 7 categories"
echo "MCP Servers: 6 (incl. rogue shell + unregistered SSE)"
echo "MCP Policies: 4 (block tool, block server, allow server, require approval)"
echo ""
echo "NOTE: MCP tools and invocations are seeded via SQL migration 064_seed_mcp_governance.sql"
echo "Run: psql -f control-plane/internal/db/migrations/064_seed_mcp_governance.sql"

rm -f "$COOKIE_FILE"

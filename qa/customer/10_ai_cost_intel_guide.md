# 10 — AI Cost Intelligence (FinOps) Guide

**Product**: AI Cost Intelligence
**Audience**: Customer FinOps / Finance / IT Leader
**API Base**: `https://api.rt19.runtimeai.io`
**FinOps API**: `https://finops.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is AI Cost Intelligence?

Track, optimize, and govern AI spend at the agent level:

- **Cost Attribution** — Per-agent, per-model, per-department cost tracking
- **Budget Management** — Spending limits with 80%/100% alerts
- **Anomaly Detection** — Flag unusual cost spikes
- **Optimization Recommendations** — Model substitution, caching, batching
- **Chargeback Reports** — Departmental cost allocation
- **Cost Forecasting** — Trend-based spend prediction

---

## Setting Up FinOps on rt19

### Step 1: Configure AI Provider Pricing

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Set up pricing for OpenAI models
curl -sf -b "$COOKIE" -X POST "$API/api/finops/pricing" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "openai",
    "models": [
      {"model": "gpt-4o", "input_cost_per_1k": 0.005, "output_cost_per_1k": 0.015},
      {"model": "gpt-4o-mini", "input_cost_per_1k": 0.00015, "output_cost_per_1k": 0.0006},
      {"model": "gpt-4-turbo", "input_cost_per_1k": 0.01, "output_cost_per_1k": 0.03}
    ]
  }'

# Set up pricing for Anthropic models
curl -sf -b "$COOKIE" -X POST "$API/api/finops/pricing" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "anthropic",
    "models": [
      {"model": "claude-opus-4-6", "input_cost_per_1k": 0.015, "output_cost_per_1k": 0.075},
      {"model": "claude-sonnet-4-6", "input_cost_per_1k": 0.003, "output_cost_per_1k": 0.015},
      {"model": "claude-haiku-4-5", "input_cost_per_1k": 0.0008, "output_cost_per_1k": 0.004}
    ]
  }'
```

### Step 2: Record Cost Events

As agents make API calls, record the token usage.

```bash
# Record a cost event
curl -sf -b "$COOKIE" -X POST "$API/api/finops/cost-events" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "<agent_id>",
    "provider": "openai",
    "model": "gpt-4o",
    "input_tokens": 1500,
    "output_tokens": 800,
    "timestamp": "2026-03-17T10:30:00Z",
    "metadata": {
      "task": "customer_support",
      "department": "support"
    }
  }'
```

### Step 3: Set Budgets

```bash
# Set monthly budget for a department
curl -sf -b "$COOKIE" -X POST "$API/api/finops/budgets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "engineering-monthly",
    "scope": {"department": "engineering"},
    "amount": 5000.00,
    "currency": "USD",
    "period": "monthly",
    "alerts": [
      {"threshold_percent": 80, "channels": ["email", "slack"]},
      {"threshold_percent": 100, "channels": ["email", "slack"], "action": "throttle"}
    ],
    "hard_limit": true,
    "hard_limit_action": "block_new_requests"
  }'

# Set per-agent budget
curl -sf -b "$COOKIE" -X POST "$API/api/finops/budgets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "support-bot-daily",
    "scope": {"agent_id": "<agent_id>"},
    "amount": 50.00,
    "currency": "USD",
    "period": "daily",
    "alerts": [
      {"threshold_percent": 90, "channels": ["email"]}
    ],
    "hard_limit": false
  }'
```

### Step 4: View Cost Dashboard

```bash
# Get cost summary
curl -sf -b "$COOKIE" "$API/api/finops/summary" | jq '{
  total_spend_mtd: .mtd_total,
  daily_average: .daily_avg,
  projected_month: .projected,
  top_agents: [.top_agents[] | {name, spend}],
  top_models: [.top_models[] | {model, spend}],
  by_department: [.departments[] | {department, spend}]
}'

# Get cost breakdown by agent
curl -sf -b "$COOKIE" "$API/api/finops/agents" | jq '.agents[] | {
  name: .agent_name,
  total_spend: .total_cost,
  tokens_used: .total_tokens,
  requests: .request_count,
  avg_cost_per_request: .avg_cost
}'

# Get cost trend (last 30 days)
curl -sf -b "$COOKIE" "$API/api/finops/trends?period=30d" | jq '.daily[] | {date, total_cost}'
```

### Step 5: Optimization Recommendations

```bash
# Get optimization recommendations
curl -sf -b "$COOKIE" "$API/api/finops/recommendations" | jq '.recommendations[] | {
  type: .type,
  description: .description,
  potential_savings: .savings,
  agent: .agent_name,
  current: .current_config,
  recommended: .recommended_config
}'
```

Example recommendations:
- **Model Substitution**: "Agent `support-bot` uses `gpt-4o` for simple tasks. Switch to `gpt-4o-mini` for 90% cost reduction."
- **Caching**: "Agent `faq-bot` asks the same 50 questions repeatedly. Enable semantic caching for 40% savings."
- **Batching**: "Agent `report-gen` makes 100 small requests/hour. Batch into 10 requests for 15% savings."
- **Idle Agent**: "Agent `test-bot-3` has zero usage in 30 days. Consider decommissioning."

### Step 6: Chargeback Reports

```bash
# Generate monthly chargeback report
curl -sf -b "$COOKIE" "$API/api/finops/chargeback?month=2026-03" | jq '{
  month: .month,
  total: .total_cost,
  departments: [.departments[] | {
    department: .name,
    cost: .total_cost,
    agents: .agent_count,
    top_model: .top_model
  }]
}'
```

---

## FinOps Dashboard Panels

| Panel | Shows |
|-------|-------|
| **Cost Overview** | MTD spend, daily trend, projected monthly |
| **Agent Cost Ranking** | Top spending agents with drill-down |
| **Model Cost Breakdown** | Spend per AI model |
| **Department Allocation** | Cost per department |
| **Budget Status** | All budgets with utilization bars |
| **Anomaly Alerts** | Unusual cost spikes |
| **Recommendations** | Optimization suggestions with savings estimate |

---

## FAQ

**Q: How does cost tracking work without a data plane?**
A: Cost events are recorded via API. Agents (or their orchestrators) POST token usage to `/api/finops/cost-events`. With a data plane, the cost ledger automatically meters tokens.

**Q: Can I set alerts without hard limits?**
A: Yes. Set `hard_limit: false` on the budget. You'll get alerts but agents won't be blocked.

**Q: What happens when a hard budget limit is hit?**
A: New requests from agents in that scope are rejected with a 429 response. Existing in-flight requests complete. The agent's sponsor is notified.

**Q: How accurate is cost attribution?**
A: As accurate as the token counts reported. For API-metered providers (OpenAI, Anthropic), token counts from the response are used. For self-hosted models, estimated token counts are used.

**Q: Can I import historical cost data?**
A: Yes. Bulk import via `POST /api/finops/cost-events/batch` with an array of events.

**Q: How does cost forecasting work?**
A: Linear regression on the last 30 days of data. For seasonality-aware forecasting, 90 days of data is recommended.

### Advanced Setup Questions

**Q: Can I integrate with my cloud billing (AWS Cost Explorer, Azure Cost Management)?**
A: Not directly yet. You can export cloud AI costs and import them as cost events. Native cloud billing integration is on the roadmap.

**Q: How does the model router for cost optimization work?**
A: The model router analyzes request complexity and routes to the cheapest model that can handle it. Simple requests → cheap model, complex requests → expensive model. This requires the data plane proxy.

**Q: Can I set up showback reports for executive review?**
A: Yes. Use `/api/finops/executive-report?month=2026-03` for a high-level summary with charts. Export as PDF or share a dashboard link.

**Q: How does semantic caching reduce costs?**
A: The cache stores embeddings of recent prompts. If a new prompt is semantically similar (>95% cosine similarity), the cached response is returned without calling the AI provider. Requires the data plane cost ledger.

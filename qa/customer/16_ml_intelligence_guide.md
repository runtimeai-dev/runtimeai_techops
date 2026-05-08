# 16 — ML Intelligence Service Guide

**Product**: ML Intelligence
**Audience**: Customer ML Engineer / Data Scientist
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is ML Intelligence?

Model registry, feature store, and hybrid edge/cloud ML scoring:

- **Model Registry** — Track and version ML models
- **Feature Store** — Centralized feature management
- **Feature Flags** — A/B testing for model variants
- **Data Pipeline Orchestration** — Manage ML data flows
- **Hybrid Edge/Cloud Scoring** — Run inference at edge or cloud
- **Real-Time Model Serving** — Low-latency model inference

---

## Current Status on rt19

> ⚠️ **ML Intelligence is in early stages.** The service binary exists but has limited API coverage. See [gaps_issues.md](gaps_issues.md) for details on what's implemented vs. planned.

### Step 1: Verify Service Health

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Check ML Intelligence service health
curl -sf "$API/api/ml/health" | jq .
# Note: This service may not be deployed on rt19 yet
```

### Step 2: Model Registry (When Available)

```bash
# Register a model
curl -sf -b "$COOKIE" -X POST "$API/api/ml/models" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "customer-churn-predictor",
    "version": "2.1.0",
    "framework": "pytorch",
    "metrics": {
      "accuracy": 0.94,
      "f1_score": 0.91,
      "auc_roc": 0.96
    },
    "tags": ["production", "churn"],
    "artifact_uri": "s3://acme-ml/models/churn-v2.1.0.pt"
  }'

# List models
curl -sf -b "$COOKIE" "$API/api/ml/models" | jq .
```

### Step 3: Feature Store (When Available)

```bash
# Create feature group
curl -sf -b "$COOKIE" -X POST "$API/api/ml/features" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "customer-behavior-features",
    "features": [
      {"name": "login_frequency", "type": "float", "description": "Average logins per week"},
      {"name": "last_active_days", "type": "int", "description": "Days since last activity"},
      {"name": "support_tickets_30d", "type": "int", "description": "Support tickets in last 30 days"}
    ],
    "source": "analytics_db",
    "refresh_interval": "hourly"
  }'
```

---

## FAQ

**Q: Is ML Intelligence production-ready?**
A: No. It's the newest product in the portfolio and has limited functionality. Model registry basics may work, but feature store and inference serving are early-stage.

**Q: Can I use MLflow instead?**
A: Yes. MLflow is a mature alternative. RuntimeAI's ML Intelligence aims to integrate with the agent governance platform (model-as-agent tracking, compliance for ML models), which MLflow doesn't cover.

**Q: When will feature store be ready?**
A: Check the product roadmap. Feature store is planned for a future release.

### Advanced Setup Questions

**Q: How does ML Intelligence integrate with the agent platform?**
A: ML models registered in the model registry can be tracked as "agent-adjacent" resources. They receive trust scores, compliance tracking, and cost attribution — the same governance applied to AI agents.

**Q: Can I run inference at the edge?**
A: Hybrid edge/cloud scoring is planned but not yet implemented. Currently, models must be served externally (e.g., via SageMaker, Vertex AI, or self-hosted).

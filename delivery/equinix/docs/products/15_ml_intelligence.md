# ML Intelligence Service Guide

**Product**: ML Intelligence | **Version**: 1.0.0

---

## Overview
Machine learning capabilities: model lifecycle management, feature store, real-time inference for risk scoring and behavioral analysis.

## Service Details

| Component | Value |
|-----------|-------|
| Port | 8095 |
| Health | `GET /health` |
| Image | `runtimeaicr.azurecr.io/ml-intelligence-service` |

## Key Features
- **Model Registry**: Track and version ML models
- **Feature Store**: Centralized feature management for inference
- **Risk Scoring**: Real-time agent risk assessment
- **Behavioral Analysis**: Anomaly detection for agent activity
- **Prediction API**: Serve model predictions for governance decisions

## Key APIs

```bash
# Health check
curl https://<YOUR_ENDPOINT>:8095/health

# Get risk score for agent
curl https://<YOUR_ENDPOINT>/api/risk-scores?tenant_id=<TENANT_ID>&agent_id=<AGENT_ID> \
  -H "Authorization: Bearer <TOKEN>"
```

## On-Prem Notes
- ML service needs access to the PostgreSQL database for feature/model storage
- Resource allocation: 500m CPU, 512Mi memory recommended for inference
- For GPU-accelerated inference, add `nvidia.com/gpu: 1` to resource requests

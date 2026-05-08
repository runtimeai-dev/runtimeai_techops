# AWS VPC Flow Logs Integration — Fully SaaS Deployment Guide

> **Version**: 1.0.0
> **Last Updated**: 2026-04-16
> **Target Environment**: RuntimeAI Fully SaaS (api.rt19.runtimeai.io)
> **Minimum Requirements**: AWS account with VPC Flow Logs enabled, Lambda runtime

---

## Overview

RuntimeAI can detect shadow AI and unauthorized LLM API calls by analyzing AWS VPC Flow Logs. This integration requires **zero agents on your endpoints** — it works by analyzing network traffic metadata to identify connections to known LLM API endpoints (OpenAI, Anthropic, AWS Bedrock, Azure OpenAI, etc.).

### What Gets Detected

| Traffic Pattern | LLM Provider | Detection Method |
|----------------|--------------|------------------|
| Traffic to `api.openai.com` | OpenAI | Destination IP/domain match |
| Traffic to `api.anthropic.com` | Anthropic | Destination IP/domain match |
| Traffic to `bedrock-runtime.*.amazonaws.com` | AWS Bedrock | Destination domain pattern |
| Traffic to `*.openai.azure.com` | Azure OpenAI | Destination domain pattern |
| Traffic to `generativelanguage.googleapis.com` | Google AI | Destination domain match |
| Traffic to `api.cohere.ai`, `api.mistral.ai`, etc. | Other providers | Destination domain match |

---

## Prerequisites

1. **AWS Account** with VPC Flow Logs enabled on target VPCs
2. **VPC Flow Log destination**: CloudWatch Logs or S3 bucket
3. **Lambda execution role** with permissions to read from the log destination
4. **RuntimeAI API credentials**: Tenant ID + API Key + Internal Service Token

---

## Architecture

```
VPC Flow Logs → CloudWatch Logs → Lambda (filter + parse) → POST /api/discovery/flow-logs/ingest → RuntimeAI CP
                                                                                                    ↓
                                                                                         Shadow AI Inbox (Dashboard)
```

---

## Step 1: Enable VPC Flow Logs

If not already enabled:

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-XXXXXXXX \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /runtimeai/vpc-flow-logs \
  --deliver-logs-permission-arn arn:aws:iam::XXXX:role/vpc-flow-log-role
```

---

## Step 2: Deploy Lambda Forwarder

Create a Lambda function that reads flow log events, filters for LLM API traffic, and forwards to RuntimeAI.

### Lambda Code (`index.py`)

```python
import json
import gzip
import base64
import urllib.request
import os

RUNTIMEAI_URL = os.environ.get("RUNTIMEAI_URL", "https://api.rt19.runtimeai.io")
TENANT_ID = os.environ["RUNTIMEAI_TENANT_ID"]
SERVICE_TOKEN = os.environ["RUNTIMEAI_SERVICE_TOKEN"]
INTEGRATION_ID = os.environ.get("RUNTIMEAI_INTEGRATION_ID", "")

def handler(event, context):
    # Decode CloudWatch Logs event
    cw_data = event.get("awslogs", {}).get("data", "")
    if not cw_data:
        return {"statusCode": 200, "body": "no data"}

    payload = json.loads(gzip.decompress(base64.b64decode(cw_data)))
    log_events = payload.get("logEvents", [])

    records = []
    for le in log_events:
        fields = le["message"].split()
        if len(fields) < 14:
            continue
        records.append({
            "source_ip": fields[3],
            "destination_ip": fields[4],
            "destination_domain": "",  # VPC flow logs don't include domain; reverse-lookup optional
            "destination_port": int(fields[6]) if fields[6].isdigit() else 0,
            "protocol": fields[7],
            "bytes_sent": int(fields[9]) if fields[9].isdigit() else 0,
            "action": fields[12],
            "flow_timestamp": "",
        })

    if not records:
        return {"statusCode": 200, "body": "no records"}

    # POST to RuntimeAI
    body = json.dumps({"records": records}).encode()
    req = urllib.request.Request(
        f"{RUNTIMEAI_URL}/api/discovery/flow-logs/ingest",
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-RuntimeAI-Internal-Token": SERVICE_TOKEN,
            "X-Tenant-ID": TENANT_ID,
            "X-Integration-ID": INTEGRATION_ID,
            "X-Cloud-Provider": "aws",
        },
    )
    resp = urllib.request.urlopen(req)
    return {"statusCode": resp.status, "body": resp.read().decode()}
```

### Deploy

```bash
# Package
zip lambda.zip index.py

# Create function
aws lambda create-function \
  --function-name runtimeai-flow-log-forwarder \
  --runtime python3.12 \
  --handler index.handler \
  --zip-file fileb://lambda.zip \
  --role arn:aws:iam::XXXX:role/runtimeai-lambda-role \
  --environment Variables="{RUNTIMEAI_TENANT_ID=<id>,RUNTIMEAI_SERVICE_TOKEN=<token>,RUNTIMEAI_URL=https://api.rt19.runtimeai.io}"

# Subscribe to CloudWatch Logs
aws logs put-subscription-filter \
  --log-group-name /runtimeai/vpc-flow-logs \
  --filter-name runtimeai-forwarder \
  --filter-pattern "" \
  --destination-arn arn:aws:lambda:us-east-1:XXXX:function:runtimeai-flow-log-forwarder
```

---

## Step 3: Register Integration in Dashboard

1. Log into `https://app.rt19.runtimeai.io`
2. Navigate to **Discovery → Cloud Integrations**
3. Click **Add Integration → AWS VPC Flow Logs**
4. Enter the Lambda ARN and AWS region
5. The integration ID will be returned — set it as `RUNTIMEAI_INTEGRATION_ID` in the Lambda env

---

## Dashboard Verification

1. Go to **Discovery → Shadow AI Inbox**
2. Filter by **Source: vpc_flow_log**
3. LLM API calls will appear with finding type `vpc_flow_llm_egress`
4. Check **Discovery → Flow Logs → Stats** for aggregate view

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Lambda not triggering | Verify CloudWatch subscription filter is active |
| `401 Unauthorized` | Check `RUNTIMEAI_SERVICE_TOKEN` is valid |
| No LLM detections | VPC flow logs don't include domain names — consider enabling DNS query logging or using Route 53 Resolver Query Logs for domain-level detection |
| High Lambda costs | Add a CloudWatch Logs filter pattern to only forward traffic on port 443 |
| Missing `destination_domain` | VPC Flow Logs v2 only includes IPs. For domain matching, deploy the eBPF tap (OPER_RT19-058) or use Route 53 query logs |

---

## Security Considerations

- Lambda has **read-only** access to CloudWatch Logs — no write permissions needed
- Service token is stored in Lambda environment (encrypt with KMS for production)
- VPC Flow Log metadata only — no packet payloads are captured
- All data transmitted over TLS (HTTPS) to RuntimeAI

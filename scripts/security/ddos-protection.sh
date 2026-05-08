#!/bin/bash
# DDoS Protection Configuration — TOPS-036

set -e

# Azure DDoS Standard (for rt19 environment)
echo "Configuring Azure DDoS Standard..."
az network ddos-protection create \
  --resource-group runtimeai-rg \
  --name runtimeai-ddos-protection \
  --location eastus2

# AWS Shield (for AWS deployments)
if [ "$CLOUD_PROVIDER" == "aws" ]; then
  echo "Configuring AWS Shield Advanced..."
  aws shield subscribe --subscription
fi

# Rate limiting at edge (Cloudflare example)
curl -X POST "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/firewall/rules" \
  -H "Authorization: Bearer \$CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Rate limit - 100 req/min per IP",
    "action": "challenge",
    "priority": 1,
    "ratelimit": {
      "characteristics": ["ip.src"],
      "period": 60,
      "threshold": 100,
      "mitigation_timeout": 86400
    }
  }'

echo "DDoS protection configured"

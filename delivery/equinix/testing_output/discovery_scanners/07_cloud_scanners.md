# Scanner 07: Cloud Scanners (AWS / Azure / GCP)
**Date**: 2026-03-27 | **Result**: 🔒 NOT TESTED (credentials needed)

## Overview
Three cloud scanners discover AI/ML workloads in cloud provider environments:

| Scanner | File | Cloud API | Discovers |
|---------|------|-----------|-----------|
| AWS | `scanners/aws_scanner.py` | Bedrock, SageMaker | Bedrock models, SageMaker endpoints |
| Azure | `scanners/azure_scanner.py` | OpenAI, Cognitive | Azure OpenAI deployments, Cognitive Services |
| GCP | `scanners/gcp_scanner.py` | Vertex AI | Vertex AI models, endpoints, pipelines |

---

## AWS Scanner

### Credentials Required
```
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
AWS_DEFAULT_REGION=us-east-1
```

### What It Scans
1. **Bedrock Models**: Lists foundation models (Claude, Titan, Llama)
2. **SageMaker Endpoints**: In-service real-time inference endpoints
3. **SageMaker Models**: Registered model artifacts

### Test Command
```bash
# Store creds in vault first:
az keyvault secret set --vault-name runtimeai-rt19-kv --name aws-access-key-id --value "$AWS_ACCESS_KEY_ID"
az keyvault secret set --vault-name runtimeai-rt19-kv --name aws-secret-access-key --value "$AWS_SECRET_ACCESS_KEY"

# Run scanner:
cd discovery && python3 -c "
from scanners.aws_scanner import scan_aws
results = scan_aws('equinix-test')
print(f'Found {len(results)} AWS agents')
for r in results: print(f'  {r[\"name\"]} ({r[\"fingerprint\"]})')
"
```

---

## Azure Scanner

### Credentials Required
```
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_ID=<your-client-id>
AZURE_CLIENT_SECRET=<your-client-secret>
AZURE_SUBSCRIPTION_ID=<your-subscription-id>
```

### What It Scans
1. **Azure OpenAI Deployments**: GPT-4, GPT-3.5-turbo deployments
2. **Cognitive Services**: Face, Speech, Vision, Language

### Test Command
```bash
cd discovery && python3 -c "
from scanners.azure_scanner import scan_azure
results = scan_azure('equinix-test')
print(f'Found {len(results)} Azure agents')
"
```

---

## GCP Scanner

### Credentials Required
```
GOOGLE_CLOUD_PROJECT=<your-project-id>
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

### What It Scans
1. **Vertex AI Models**: Listed in the project
2. **Vertex AI Endpoints**: Active serving endpoints
3. **Vertex AI Pipelines**: ML pipeline runs

### Test Command
```bash
cd discovery && python3 -c "
from scanners.gcp_scanner import scan_gcp
results = scan_gcp('equinix-test')
print(f'Found {len(results)} GCP agents')
"
```

---

## Providing Credentials
Store all cloud credentials in Azure Key Vault:
```bash
az keyvault secret set --vault-name runtimeai-rt19-kv --name <secret-name> --value "<value>"
```

Then mount as K8s secrets for the discovery pod:
```yaml
env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: rt19-cloud-scanner-secrets
        key: aws-access-key-id
```

# User Action Items — Equinix SoW Delivery

Items that require your intervention (credentials, external configs, etc.)

## Action Required

### 1. 🔧 SIEM Configuration (#12)
After the fix is deployed, configure SIEM with your actual endpoint:
```bash
# Authenticate first
EQIX_PASS=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name equinix-demo-admin-password --query value -o tsv)
curl -c /tmp/ck.txt -X POST "https://api.rt19.runtimeai.io/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"equinix-demo\",\"email\":\"admin@equinix-demo.runtimeai.io\",\"password\":\"$EQIX_PASS\"}"

# Configure Splunk (example)
curl -b /tmp/ck.txt -X PUT "https://api.rt19.runtimeai.io/api/siem/config" \
  -H "Content-Type: application/json" \
  -d '{"provider_type":"splunk","url":"https://your-splunk:8088/services/collector","token":"YOUR_HEC_TOKEN","enabled":true}'
```

### 2. 🔧 Jira Ticketing (#13)
Configure Jira integration for the equinix-demo tenant. This requires:
- Jira Cloud instance URL
- API token or OAuth credentials
- Project key for RuntimeAI tickets

### 3. 🔧 GitHub App (#20)
To test GitHub agent scanning, install the RuntimeAI GitHub App on an Equinix test organization:
- Navigate to the dashboard → Integrations → GitHub
- Follow the OAuth flow to install

### 4. 🔑 AWS/GCP Cloud Scanner Credentials
For cloud AI resource discovery:
- **AWS**: Create a read-only IAM user with `AmazonBedrockReadOnly` + `AmazonSageMakerReadOnly` policies
- **GCP**: Create a service account with `roles/aiplatform.viewer`
- Store creds in vault:
```bash
az keyvault secret set --vault-name runtimeai-rt19-kv --name aws-scanner-access-key --value "AKIA..."
az keyvault secret set --vault-name runtimeai-rt19-kv --name aws-scanner-secret-key --value "..."
```

## No Action Required (automated)
- ✅ Bot-CA port fix — auto-deployed
- ✅ DLP scanner — auto-deployed
- ✅ SIEM tenant_id — auto-deployed  
- ✅ RLS migration 098 — runs on pod startup

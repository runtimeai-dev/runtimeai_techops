# How to deploy — RuntimeAI platform

> Operational complement to `todo-list/TOPS-022-deployment-ownership-model.md` (the policy). This doc is the concrete commands.
> When in doubt, read the policy first to know which repo owns the change you're making.

---

## The 30-second version

```
Code change in a product service?
  → cd <product-repo>
  → bash deployment/scripts/build-push-deploy.sh <service>
  → kubectl -n <ns> set image deployment/<svc> <container>=runtimeaicr.azurecr.io/<repo>:<NEW_TAG>
  → kubectl rollout status, then smoke-test the live URL

Infra change (helm release, PDB, NetworkPolicy)?
  → cd runtimeai_techops
  → edit k8s/<service>/<file>.yaml
  → kubectl apply -f k8s/<service>/<file>.yaml   (or helm upgrade -f values.yaml)

Secret rotation?
  → az keyvault secret set --vault-name runtimeai-rt19-kv --name <key> --value <new>
  → bash runtimeai_techops/scripts/secrets/create-secrets.sh rt19
  → kubectl rollout restart deployment/<dependent-services>
```

---

## Per-product deploy commands

### runtimeai (auth-service, landing, SaaS Admin, MCP Gateway, AI FinOps, eSign, etc.) + runtimeai-enterprise (control-plane, dashboard, flow-enforcer, drift, WAF, cost-ledger, vendor-wrapper)

Both share the rt19 deploy script:

```bash
cd /Users/roshanshaik/work/runtimeai-enterprise
bash deployment/scripts/rt19/build-push-deploy.sh <service-name>
# Examples: auth-service | control-plane | dashboard | flow-enforcer | esign-service | esign-landing
```

Landing services (namespace `runtimeai-landing` — runtimeai.io, www, trial):
```bash
NAMESPACE=runtimeai-landing bash deployment/scripts/rt19/build-push-deploy.sh website-singlepage
```

### runtimecrm (ARH + Console)

Own deploy script (lives in the repo):
```bash
cd /Users/roshanshaik/work/runtimecrm
bash deployment/scripts/build-push-deploy.sh                    # all
bash deployment/scripts/build-push-deploy.sh arh
bash deployment/scripts/build-push-deploy.sh runtimecrm-console
```

### pq_data_platform (QuantumVault, PQ Sign, PQ Comply, 10 PQC services)

⚠️ The repo's `deployment/rt19/build-push-deploy.sh` is **outdated** (uses old `qutonomous/` ACR path). Do not use it. Build manually:

```bash
az acr login --name runtimeaicr
TAG=$(date +%Y%m%d-%H%M)
cd /Users/roshanshaik/work/pq_data_platform
docker buildx build --platform linux/arm64 \
  --tag runtimeaicr.azurecr.io/pqdata/<service>:latest \
  --tag runtimeaicr.azurecr.io/pqdata/<service>:${TAG} \
  --file services/<service>/Dockerfile services/<service> --push
kubectl set image deployment/<service> -n pqdata <service>=runtimeaicr.azurecr.io/pqdata/<service>:${TAG}
kubectl rollout status deployment/<service> -n pqdata
```

### agentic_platform (KYA, Cost Control, Fraud Shield, Audit Black Box, etc.)

All 15 services currently **Planned** — no live K8s yet. When deployment lands, add command here.

---

## Mandatory: `kubectl set image` after EVERY `build-push-deploy.sh`

This is the deploy gotcha that has burned us **at least four times** in the past 60 days. The script pushes `:latest` + `:<TAG>` to ACR, runs `kubectl rollout restart`, but the deployment spec still has the OLD pinned tag. Pods restart on the OLD image even with `imagePullPolicy: Always`.

**Worse**: a subsequent `kubectl set env` (used to add config) triggers a rollout that pulls the deployment's pinned tag → can **roll back** an image you just pushed.

After every `build-push-deploy.sh <service>`:

```bash
# Pull the new tag from the script's output (always YYYYMMDD-HHMM format)
NEW_TAG=$(az acr repository show-tags --name runtimeaicr --repository <repo>/<service> --orderby time_desc --top 1 -o tsv)
kubectl -n <ns> set image deployment/<service> <container>=runtimeaicr.azurecr.io/<repo>/<service>:${NEW_TAG}
until kubectl -n <ns> get pods -l app=<service> -o jsonpath='{.items[*].spec.containers[0].image}' | tr ' ' '\n' | sort -u | wc -l | grep -q '^1$'; do sleep 3; done
echo "deployed: ${NEW_TAG}"
```

The `until` loop guards against the rolling-update window where half the pods are on the old tag.

---

## Cross-product / cross-repo deploys

When a change spans multiple repos (e.g. RCRM-033 BUG-001 which touched runtimeai + runtimeai-enterprise + runtimecrm), the order matters.

**General principle:** deploy the upstream service first. A new field consumed by a downstream service must exist on the upstream's response before the downstream learns about it.

Example: auth-service runtimecrm persona (RCRM-033, 2026-05-10)
1. runtimeai (auth-service) — defines the new persona, builds the new verify URL.
2. runtimeai-enterprise (control-plane) — handles the new `?portal=runtimecrm` query.
3. runtimecrm (console) — actually sends `persona: 'runtimecrm'`.

The reverse order ships a console that immediately errors against an auth-service that doesn't know the persona.

For every cross-repo deploy:
- Make a `CHANGELOG.md` entry in `runtimeai_techops/CHANGELOG.md` documenting the order + the env vars set + the smoke test.
- Link each product-repo PR from that entry so future operators can trace it.

---

## Shared infra (helm releases, cluster-wide K8s)

### ingress-nginx
```bash
cd /Users/roshanshaik/work/runtimeai_techops
# Update values
$EDITOR k8s/ingress-nginx/values.yaml
# Apply
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx -f k8s/ingress-nginx/values.yaml --version 4.15.0
# PDB and similar standalone manifests
kubectl apply -f k8s/ingress-nginx/poddisruptionbudget.yaml
```

### Other shared infra (currently un-tracked, TOPS-023)
```bash
# cert-manager, prometheus, grafana, redis, postgres — these are live but
# their helm values are NOT in techops yet. Until TOPS-023 closes:
helm get values <release> -n <namespace> > /tmp/<release>-current-values.yaml
# Edit and re-apply, OR commit to techops first then apply.
```

---

## Secrets

### Add a new secret value

```bash
# 1. Put in Azure Key Vault (source of truth)
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name my-secret-key --value "..."

# 2. Add to the secret-creation script if it's not generic
$EDITOR /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/create-secrets.sh

# 3. Push to K8s
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/create-secrets.sh rt19

# 4. Restart dependent deployments
kubectl -n <ns> rollout restart deployment/<svc>
```

### Rotate an existing secret

```bash
# 1. Generate new value, update KV
az keyvault secret set --vault-name runtimeai-rt19-kv --name <existing-key> --value <new>
# 2. Re-run secret creation script
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/create-secrets.sh rt19
# 3. Roll dependent deployments — by spec they should re-read the secret on restart
kubectl -n <ns> rollout restart deployment/<svc>
```

### QuantumVault-backed secrets (preferred for product credentials)

For OAuth clients, API keys, etc. that the product fetches at startup:
```bash
bash /Users/roshanshaik/work/runtimecrm/qa_testing_local/qv_put_secret.sh \
  runtimecrm/<path> key=value [key=value ...]
# ARH (and any future QV-aware service) picks it up on next restart.
```

QV-backed wins over K8s Secret when:
- Multiple services need the same credential and you want one source of truth.
- The value rotates often.
- It's a customer-specific credential and you don't want to mirror it cluster-wide.

---

## Recovery — common failure modes

### "Site is down" (external TCP timeout to LB IP)

Symptoms:
- `curl https://app.runtimecrm.com/login` → exit 28 (timeout)
- `nc -zv -w 5 <LB-IP> 443` → timeout
- `kubectl run --image=curlimages/curl ... curl https://...` from inside cluster → 200
- Azure activity log: `Microsoft.ResourceHealth` event on the LB (NOT Service Health — that's region-wide)

Recovery (60 seconds):
```bash
kubectl -n ingress-nginx rollout restart deployment/ingress-nginx-controller
```

Full diagnosis runbook: `runtimeai_techops/k8s/ingress-nginx/README.md`.

### Deployed image isn't running

Symptoms:
- Just pushed `<service>:20260510-1730` to ACR
- `kubectl rollout status` says success
- But `curl <svc>/healthz` returns old version

Recovery:
```bash
kubectl -n <ns> get pods -l app=<service> -o jsonpath='{.items[*].spec.containers[0].image}' | tr ' ' '\n' | sort -u
# Likely shows the OLD tag. Force:
kubectl -n <ns> set image deployment/<service> <container>=runtimeaicr.azurecr.io/<repo>/<service>:<NEW_TAG>
```

### auth-service rate-limited during testing

Symptoms:
- `POST /api/auth/magic-link` returns `{"error":"rate_limit_exceeded"}`

Recovery (in-memory limiter — redis flush DOES NOT clear it):
```bash
kubectl -n rt19 rollout restart deployment/auth-service
```

### ARH 401s on every endpoint despite valid session

Symptoms:
- `/api/auth/me` returns 200
- `/api/v1/*` returns 401

Cause: ARH's `CONTROL_PLANE_URL` is unset → defaults to `control-plane:8080` (same-ns short name) → DNS fail because CP is in `rt19`.

Recovery:
```bash
kubectl -n runtimecrm set env deployment/arh \
  CONTROL_PLANE_URL=http://control-plane.rt19.svc.cluster.local:8080
```

(This should be in the `arh-deployment.yaml` manifest. TOPS-026 will audit.)

---

## What this doc explicitly does NOT cover

- Image vulnerability scanning + patching cycles (TOPS-013, separate doc)
- SOC 2 audit log requirements (`runtimeai_techops/docs/compliance/`)
- Production failover / DR (rt01/rt02 cluster pair — see `runbooks/dr-failover.md`)
- New cluster bootstrap (`scripts/deploy/bootstrap.sh`)
- Customer-tenant provisioning (per-product — see each product repo's tenant onboarding)

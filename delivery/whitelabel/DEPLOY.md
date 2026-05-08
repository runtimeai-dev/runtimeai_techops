# RuntimeAI White-Label Deployment Runbook (Model B)

> Audience: Partner ops engineer (Scorpius Networks et al.)
> Target: K8s cluster on GCP / AWS / Azure with kubectl + helm pre-installed.

---

## 0. Prerequisites

| Requirement | How to check |
|-------------|--------------|
| K8s cluster (1.27+) | `kubectl version` |
| `helm` 3.12+ | `helm version` |
| `kubectl` reachable from this shell | `kubectl get ns` |
| Outbound HTTPS to `license.runtimeai.io` | `curl -sI https://license.runtimeai.io/healthz` |
| Cloud-provider managed services (skip if `--cloud=quickstart`) | see below |

**Bundle scope** — this tarball contains exclusively: Control Plane, Data Plane, MCP Gateway, AIW (Module A). It does **not** contain NHI, Cloud Security, Kinetic AI, QuantoSign, Qutonomous, AEP, or MCP Servers. The license JWT enforces this — any attempt to call those modules returns `402 module_not_licensed`.

---

## 1. Cloud-specific managed-service provisioning

### GCP

```bash
# Cloud SQL (Postgres 15)
gcloud sql instances create runtimeai-cp \
  --database-version=POSTGRES_15 --tier=db-custom-2-7680 --region=us-central1
gcloud sql databases create runtimeai --instance=runtimeai-cp
export DATABASE_URL="postgresql://runtimeai:${DB_PASSWORD}@/runtimeai?host=/cloudsql/PROJECT:us-central1:runtimeai-cp"

# Memorystore (Redis 7)
gcloud redis instances create runtimeai-redis --size=1 --region=us-central1
export REDIS_URL="redis://${REDIS_IP}:6379/0"

# GCS for blob assets
gsutil mb -l us-central1 gs://runtimeai-${PARTNER}-assets
export BLOB_BUCKET=runtimeai-${PARTNER}-assets
```

### AWS

```bash
# RDS Postgres
aws rds create-db-instance \
  --db-instance-identifier runtimeai-cp \
  --engine postgres --engine-version 15 \
  --db-instance-class db.t3.medium --allocated-storage 50 \
  --master-username runtimeai --master-user-password "${DB_PASSWORD}"
export DATABASE_URL="postgresql://runtimeai:${DB_PASSWORD}@${RDS_ENDPOINT}/runtimeai?sslmode=require"

# ElastiCache
aws elasticache create-cache-cluster --cache-cluster-id runtimeai-redis \
  --engine redis --cache-node-type cache.t3.medium --num-cache-nodes 1
export REDIS_URL="redis://${ELASTICACHE_ENDPOINT}:6379/0"

# S3 bucket
aws s3 mb s3://runtimeai-${PARTNER}-assets --region us-east-1
export BLOB_BUCKET=runtimeai-${PARTNER}-assets
```

### Azure

```bash
az postgres flexible-server create \
  --name runtimeai-cp --resource-group runtimeai-rg \
  --location eastus --tier GeneralPurpose --sku-name Standard_D2s_v3 \
  --version 15 --admin-user runtimeai --admin-password "${DB_PASSWORD}"
export DATABASE_URL="postgresql://runtimeai:${DB_PASSWORD}@runtimeai-cp.postgres.database.azure.com/runtimeai?sslmode=require"

az redis create --name runtimeai-redis --resource-group runtimeai-rg \
  --location eastus --sku Basic --vm-size c1
export REDIS_URL="redis://${REDIS_HOST}:6380/0?ssl=true"

az storage account create --name runtimeai${PARTNER}assets \
  --resource-group runtimeai-rg --location eastus --sku Standard_LRS
export BLOB_BUCKET=runtimeai${PARTNER}assets
```

### Quickstart (POC / dev only)

`./install.sh --cloud=quickstart` deploys single-node Postgres + Redis as in-cluster StatefulSets. Acceptable for a 1–2 week POC; **never** for production. No backup, no HA, no managed cert-manager TLS for the data plane.

---

## 2. Get partner service-account credentials

Required for call-home + monthly attestation submission. RuntimeAI ops issues these via the SaaS Admin Partner Admin Portal:

```
SaaS Admin (admin.runtimeai.io) → Partner Admin → <your partner row>
                              → Brand Assets tab
                              → "Create Credentials" or "Rotate"
```

You receive `client_id` + `client_secret` **once** in a modal — copy both immediately. Pass them to `install.sh` as env vars.

---

## 3. Run the installer

```bash
export DATABASE_URL="..."          # from §1
export REDIS_URL="..."             # from §1
export BLOB_BUCKET="..."           # from §1
export PARTNER_CLIENT_ID="..."     # from §2
export PARTNER_CLIENT_SECRET="..." # from §2
export RUNTIMEAI_DOMAIN="platform.scorpius.com"   # the domain customers reach
export RUNTIMEAI_INSTANCE_TYPE="cp"               # one of: cp, dp
export RUNTIMEAI_INSTANCE_ID="cp-us-east"         # human label, [a-z0-9-]{1,64}

./install.sh --cloud=gcp --license=license.jwt
```

The script:

1. Verifies the tarball SHA256 (supply-chain integrity).
2. Creates the K8s namespace.
3. Stores the license JWT, partner credentials, DSN/REDIS_URL, and instance metadata as Secrets.
4. Reads the cluster UID (`kubectl get ns kube-system -o jsonpath='{.metadata.uid}'`) and exports it for the fingerprint.
5. Applies the cloud-specific Helm overlay (`values.yaml` + `values-<cloud>.yaml`).
6. Helm upgrades/installs the `runtimeai` release.

CP and MCP-gateway pods come up. On first start, CP:
- Verifies the license JWT signature (Ed25519 against embedded public keys).
- Calls `POST license.runtimeai.io/api/v1/activate` to register its fingerprint.
  - `409 activation_conflict` → exits 1 (license already activated elsewhere).
- Starts the call-home goroutine (heartbeat every 24h by default).

---

## 4. Verify the install

```bash
# CP healthy
kubectl -n runtimeai get pods -l app=control-plane
kubectl -n runtimeai logs -l app=control-plane | grep -E "license:|callhome"
# Expect: "[license] OK: bundle=guardian ..."
# Expect: "[license] activated: ..."
# Expect: "[license] call-home agent started: ..."

# MCP gateway healthy
kubectl -n runtimeai get pods -l app=mcp-gateway

# In SaaS Admin (RuntimeAI side) — the Customers tab under your partner row
# should show this deployment within ~2 minutes.
```

---

## 5. Upgrade procedure

Upgrades are versioned releases pushed to `releases/<partner_slug>/<version>/`.

```bash
# Download the new tarball
curl -L https://assets.runtimeai.io/releases/scorpius/1.1.0/runtimeai-whitelabel-scorpius-1.1.0.tar.gz -o release.tar.gz
# Verify checksum (matches the row in Partner Admin → Releases tab)
shasum -a 256 -c sha256.txt
tar -xzf release.tar.gz
./install.sh --cloud=gcp --license=license.jwt   # re-run; helm upgrades in place
```

The license JWT carries a `min_version` field. If the binary you're running is below `min_version`, CP refuses to start and logs:

```
[license] FATAL: binary version "1.0.0" is below license min_version "1.1.0" — upgrade required
```

RuntimeAI ops can raise `min_version` from the Partner Admin → Releases tab when a security fix needs to roll out. Plan to deploy upgrades within 30 days of `min_version` bumps.

---

## 6. Call-home & enforcement

Every `whitelabel.call_home_interval_hours` (default 24h), CP:
1. Mints a partner JWT via `/api/v1/partner/token`.
2. Posts `{jti, version, aiw_count, customer_count, mcp_invocations, fingerprint, instance_id}` to `/api/v1/callhome`.
3. On transient failure, retries with exponential backoff (5s → 30s → 5m → 30m → next interval).

**If call-home is silent for `call_home_hard_cutoff_hours` (default 72h):**
- CP enters **grace mode** — writes still allowed, console banner appears.
- 24h later → **read-only**, write endpoints return 402.
- Resume on next successful call-home.

**Air-gap deployments** (`features.air_gap=true` in license JWT) skip call-home entirely. Only available for international full-whitelabel partners; US co-branded licenses cannot have `air_gap=true`.

---

## 7. Monthly revenue attestation

```bash
# Submit gross ARR for the month
TOKEN=$(curl -sX POST https://license.runtimeai.io/api/v1/partner/token \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"'$PARTNER_CLIENT_ID'","client_secret":"'$PARTNER_CLIENT_SECRET'"}' \
  | jq -r '.access_token')

curl -X POST https://license.runtimeai.io/api/v1/attestation \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"period":"2026-05","gross_arr":120000.00,"customer_count":12,"notes":"Q2 onboarding"}'
```

RuntimeAI computes the 75/25 split, flags below-floor pricing, and ops confirms in SaaS Admin. Cross-checked against your live call-home telemetry.

---

## 8. Known issues / FAQ

- **"License already activated on another deployment" on first start** — your previous deployment's fingerprint is still registered. Open a support ticket — RuntimeAI ops can perform `POST /api/v1/licenses/{jti}/reset-fingerprint` (max 3 resets per JTI per 12 months).
- **Cluster UID changed unexpectedly** (cluster rebuild) — same as above, request a fingerprint reset.
- **Cert-manager challenge fails** — ensure the partner CNAME has propagated and port 80 reaches the ingress before re-applying.
- **Postgres password rotation** — ALTER USER, then update the `runtimeai-config` Secret, then `kubectl rollout restart deploy/control-plane`.

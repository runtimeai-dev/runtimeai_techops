# RuntimeAI Image Registry Guide

## Image Naming Convention

All RuntimeAI container images follow this naming pattern:

```
ghcr.io/runtimeai-dev/<service>:<tag>
```

### Available Images

| Service | Image | Description |
|---------|-------|-------------|
| Control Plane | `ghcr.io/runtimeai-dev/control-plane` | Core API server |
| Auth Service | `ghcr.io/runtimeai-dev/auth-service` | Authentication & JWT |
| Dashboard | `ghcr.io/runtimeai-dev/dashboard` | React web UI |
| MCP Gateway | `ghcr.io/runtimeai-dev/mcp-gateway` | MCP tool gateway |
| Flow Enforcer | `ghcr.io/runtimeai-dev/flow-enforcer` | Envoy + Wasm sidecar |
| WAF | `ghcr.io/runtimeai-dev/waf` | Web Application Firewall |
| Data Proxy | `ghcr.io/runtimeai-dev/data-proxy` | Data exfiltration prevention |
| Cost Ledger | `ghcr.io/runtimeai-dev/cost-ledger` | FinOps cost tracking |
| Identity DNS | `ghcr.io/runtimeai-dev/identity-dns` | Agent identity resolution |
| Drift Engine | `ghcr.io/runtimeai-dev/drift-engine` | Configuration drift detection |
| Discovery | `ghcr.io/runtimeai-dev/discovery-service` | Shadow AI discovery |
| eSign | `ghcr.io/runtimeai-dev/esign-service` | Document signing |
| Marketplace | `ghcr.io/runtimeai-dev/marketplace-service` | Plugin marketplace |
| AI FinOps | `ghcr.io/runtimeai-dev/ai-finops-service` | AI cost analytics |

### Tag Strategy

| Tag Pattern | Example | Description |
|-------------|---------|-------------|
| `v<semver>` | `v1.0.0` | Release version |
| `v<major>.<minor>` | `v1.0` | Latest patch in minor |
| `sha-<short>` | `sha-abc1234` | Specific commit |
| `latest` | `latest` | Most recent release |
| `v<semver>-rc.<n>` | `v1.0.0-rc.1` | Release candidate |

### Multi-Architecture Support

All images are built for both architectures:
- `linux/amd64` (x86_64)
- `linux/arm64` (Apple Silicon, Graviton)

---

## Customer Access Setup

RuntimeAI images are **private** on GHCR. Customers need a Personal Access Token (PAT) to pull images.

### Step 1: Create a GitHub PAT

1. Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens
2. Create a new token with:
   - **Repository access**: `runtimeai-dev/runtimeai-enterprise`
   - **Permissions**: `Packages: Read` (read-only)
3. Copy the token value

### Step 2: Docker Login

```bash
echo "YOUR_PAT_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### Step 3: Kubernetes imagePullSecret

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_PAT_TOKEN \
  --docker-email=YOUR_EMAIL \
  -n your-namespace
```

Then reference it in your deployments:

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull-secret
  containers:
    - name: control-plane
      image: ghcr.io/runtimeai-dev/control-plane:v1.0.0
```

### Step 4: Verify Access

```bash
# Pull a test image
docker pull ghcr.io/runtimeai-dev/control-plane:latest

# Verify multi-arch manifest
docker manifest inspect ghcr.io/runtimeai-dev/control-plane:latest
```

---

## Supply Chain Security

### Cosign Verification

All images are signed with [cosign](https://github.com/sigstore/cosign) using keyless signing via GitHub OIDC.

```bash
# Install cosign
brew install cosign  # macOS
# or: go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Verify an image
cosign verify ghcr.io/runtimeai-dev/control-plane:v1.0.0 \
  --certificate-identity-regexp="https://github.com/runtimeai-dev/.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

### SBOM

Each image has an attached SBOM (Software Bill of Materials) in SPDX format:

```bash
# Download SBOM
cosign download sbom ghcr.io/runtimeai-dev/control-plane:v1.0.0 > sbom.spdx.json
```

---

## Offline / Air-Gapped Deployment

For air-gapped environments, use the offline bundle export script:

```bash
# Export all images for a version
./deployment/scripts/export_images.sh v1.0.0

# Transfer to air-gapped host
scp -r offline-bundle/ target-host:~/

# On the air-gapped host: load images
cd ~/offline-bundle && ./load_images.sh

# Optionally retag for a private registry
./load_images.sh --retag my-registry.local:5000
```

---

## Public Packages

The following packages are **publicly accessible** (no PAT required):

| Package | Registry | Install Command |
|---------|----------|----------------|
| `@runtimeai/sdk` | npm | `npm install @runtimeai/sdk` |
| `runtimeai` | PyPI | `pip install runtimeai` |
| `runtimeai-cli` | Homebrew | `brew install runtimeai-dev/tap/runtimeai-cli` |
| `runtimeai-cli` | GitHub Releases | Download from Releases page |

Container images remain **private** and require customer PAT access.

# MCP Gateway — Air-gap Helm chart (OPER_RT19-084t)

Single-cluster, on-prem-friendly install of the RuntimeAI MCP gateway +
6 servers. Designed for environments without internet access.

## Prerequisites

1. Kubernetes 1.30+ with cert-manager + ingress-nginx pre-installed.
2. A private OCI registry mirror (Harbor / GHCR Enterprise / ACR Air-Gap).
3. The offline image bundle (provided separately): `mcp-bundle-1.0.0.tar`.
4. A reachable Postgres 15+ (FQDN + DSN).
5. A Bot-CA root cert PEM.

## Install

```bash
# 1. Load bundled images into your private registry
docker load -i mcp-bundle-1.0.0.tar
for img in mcp-gateway mcp-server-quantosign mcp-server-qutonomous mcp-server-runtimeai mcp-server-postgresql; do
  docker tag runtimeaicr.azurecr.io/$img:1.0.0 registry.example.com/runtimeai/$img:1.0.0
  docker push registry.example.com/runtimeai/$img:1.0.0
done

# 2. Customise values
cp values.yaml my-values.yaml
# Edit: gateway.image.repository, servers.<name>.image, postgres.dsn,
# botCa.rootCAPemBase64 (base64 of your Bot-CA root PEM), ingress.host

# 3. Install
helm install mcp-gateway ./mcp_gateway/helm -f my-values.yaml -n mcp --create-namespace
```

## Verification

```bash
kubectl -n mcp get pods               # gateway 2/2 + servers 1/1 each
curl -k https://<ingress-host>/healthz
```

## Out of scope for v1

- Bot-CA service itself (assumed pre-installed; chart consumes its root cert)
- Postgres operator (assumed pre-installed; chart consumes its DSN)
- Backup automation (operator's responsibility per local policy)

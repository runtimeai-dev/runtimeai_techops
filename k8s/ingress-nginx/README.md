# ingress-nginx — cluster ingress controller (rt19)

## Why this directory exists

After the 2026-05-10 outage (Microsoft.ResourceHealth event 16:21 UTC) we learned the cluster ingress was running 1 replica with no PDB. A single stale LB registration brought down every external surface: `app.runtimecrm.com`, `www.runtimeai.io`, `trial.runtimeai.io`, `admin.runtimeai.io`, `app.rt19.runtimeai.io`. Recovery was a 30-second `kubectl rollout restart` once we found the root cause, but we lost ~3 hours of customer reachability before someone noticed and reported it.

This directory exists so the next operator can:
1. Re-deploy ingress-nginx reproducibly via helm with values.yaml.
2. See the PodDisruptionBudget and anti-affinity that the cluster expects to have.
3. Find the runbook for the next "the site is down" call.

## Files

| File | What |
|------|------|
| `values.yaml` | Helm values for `ingress-nginx/ingress-nginx` chart. 2 replicas, hard anti-affinity by hostname, raised resource floors. |
| `poddisruptionbudget.yaml` | `minAvailable: 1` so AKS maintenance can't drain both replicas at once. |

## How to apply

```bash
# First time (or after a chart-version bump):
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f k8s/ingress-nginx/values.yaml \
  --version 4.15.0

# Apply the standalone PDB:
kubectl apply -f k8s/ingress-nginx/poddisruptionbudget.yaml
```

The PDB is intentionally a separate manifest rather than `controller.podDisruptionBudget` in the chart, so it surfaces in `kubectl get pdb -A` without parsing helm release state.

## Symptoms of recurrence

- External `curl https://app.runtimecrm.com/login` times out at TCP handshake (`curl exit code 28`).
- `nc -zv -w 5 20.59.41.161 443` times out.
- `kubectl run --image=curlimages/curl ... curl https://app.runtimecrm.com/login` (inside cluster) returns **200**. This proves the apps + ingress controller are alive; the LB → pod path is what's broken.
- Azure activity log shows a `Microsoft.ResourceHealth` event activated on `MICROSOFT.NETWORK/LOADBALANCERS/KUBERNETES`. Azure **Service Health** dashboard will NOT show this — it's per-resource (ResourceHealth), not region-wide (ServiceHealth).

## Recovery (60 seconds)

```bash
kubectl -n ingress-nginx rollout restart deployment/ingress-nginx-controller
```

The new pod re-registers with the Azure LB cleanly. Reachability returns within 1–2 minutes (LB health probe interval is 5s, threshold is 2 probes).

## Recommended next P1 — external synthetic probe

We have no external eyes on the front door. The 2026-05-10 outage was found because a human noticed a blank page. Two options worth wiring up:

1. **Azure Application Insights availability test** — cheap, native, alerts to email/Slack/PagerDuty. Targets `https://app.runtimecrm.com/healthz` and `https://runtimeai.io/`, alerts when TCP timeout > 5s or status != 200 from 3+ locations.
2. **Uptime Robot or similar third-party** — also fine, just outside Azure.

Decision deferred until we pick a paging integration. For now, the PDB + replicaCount=2 + anti-affinity makes a single-pod recurrence un-correlated with a full outage.

## Audit trail

| Date | Change | By |
|------|--------|----|
| 2026-05-10 | Initial commit (techops/RCRM-033-ingress-resilience). Captured post-incident state. | post-RCRM-033 incident response |

# TOPS-022 — Deployment ownership model: techops vs product repos

> Companion spec: `runtimeai/todo-list/OPS-001-deployment-ownership-model.md` (identical content, mirrored so product teams find it without crossing repos).
> Runbook: `runtimeai_techops/docs/runbooks/how-to-deploy.md`.

## Why this spec exists

The 2026-05-10 outage (3-hour external blackout across runtimecrm + runtimeai.io + trial + admin + rt19 dashboards) surfaced a real ambiguity: when something breaks, which repo do I open? When I want to change ingress-nginx, do I edit the helm release directly or do I commit a manifest somewhere? Different ops people did different things over the past 60 days and the cluster's source of truth diverged.

This spec sets the line clearly. Future operators (and the future AI agents that help them) read this once and stop guessing.

---

## The line

**If it would survive a cluster rebuild → `runtimeai_techops`.**
**If it's per-deployment image build / product code → the product repo.**

That's the whole rule. Everything below is application.

## Ownership matrix

| Layer | Source of truth | Why |
|------|-----------------|-----|
| Product images (arh, console, control-plane, auth-service, esign-service, dashboard, landing, mcp-gateway, ai-finops, etc.) | Each product repo's `Dockerfile` + `deployment/scripts/build-push-deploy.sh` | Source code travels with the build script. Splitting them slows every PR. |
| Product K8s manifests (Deployment, Service, HPA, PDB, Ingress, ConfigMap) | Each product repo's `deployment/k8s/*.yaml` | Tightly coupled to the image's env vars + ports. Lives next to the code that depends on it. |
| Product migrations | Each product repo's `migrations/` | Same reasoning. Auto-applied by the service on startup or by a Job in the manifest. |
| Cluster shared infra: ingress-nginx, cert-manager, prometheus, grafana, alertmanager, redis (shared), postgres (shared) | `runtimeai_techops/k8s/<service>/` | Cluster-wide. If we lose the cluster, we rebuild from these. Product repos must NOT touch. |
| Helm release values for shared infra | `runtimeai_techops/k8s/<service>/values.yaml` | Reproducibility on cluster rebuild. Today only ingress-nginx has this — TOPS-023 to backfill the rest. |
| Cluster-wide RBAC, NetworkPolicy, namespaces, pod-security profiles | `runtimeai_techops/k8s/<ns>/` (per namespace) or `k8s/cluster/` | Cluster security baseline. Audited by SOC 2 / FedRAMP. |
| Secrets templates (`*.template`, `*.example`) | `runtimeai_techops/secrets-templates/` | Real values live in Azure Key Vault. Templates show the shape. |
| Real secrets | Azure Key Vault `runtimeai-rt19-kv` / `runtimeai-prod-kv` | Never in git, never in K8s ConfigMap. Injected at deploy time via `scripts/secrets/create-secrets.sh`. |
| Per-cluster Terraform (Azure VNet, AKS, public IPs, Front Door) | `runtimeai_techops/terraform/<cloud>/` | Foundational. Plan + apply through ops review. |
| Cross-repo deployment orchestration (the "to ship X, do A then B then C" recipe) | `runtimeai_techops/CHANGELOG.md` + `runtimeai_techops/docs/runbooks/` | Audit trail of what shipped together; recovery instructions. Not in any one product repo. |
| Synthetic probes / external monitoring | `runtimeai_techops/monitoring/` | Watches the cluster from outside. TOPS-024 to build it out. |
| QA test suites that exercise multiple products end-to-end | `runtimeai_techops/qa/` | Cross-product. Single-product test suites live in the product repo (`<repo>/qa_testing_local/`). |

## Practical "where does this change go" decision tree

```
I want to change <thing>:

  ├── ...the image, code, or single-service manifest?
  │       → product repo. PR there. Deploy via that repo's build-push-deploy.sh.
  │
  ├── ...the ingress controller / cert-manager / prometheus / a helm release for shared infra?
  │       → runtimeai_techops/k8s/<service>/. PR there. Apply via helm upgrade or kubectl apply.
  │
  ├── ...a secret value (rotate, add a new key)?
  │       → Azure Key Vault first. Then `runtimeai_techops/scripts/secrets/create-secrets.sh <env>`
  │         pushes it into K8s. Never commit the real value anywhere.
  │
  ├── ...the runbook for a known failure mode?
  │       → runtimeai_techops/docs/runbooks/<service>.md.
  │
  ├── ...the cross-product deploy order for a feature spanning 2+ repos?
  │       → runtimeai_techops/CHANGELOG.md entry, PLUS the actual code PRs in each product repo.
  │
  ├── ...the cluster (new node pool, new public IP, network policy)?
  │       → runtimeai_techops/terraform/azure/ or k8s/cluster/. PR + plan review.
  │
  └── ...the deploy script itself?
          → If it's product-specific: product repo's deployment/scripts/.
            If it's cluster-wide (e.g. rotate all secrets): runtimeai_techops/scripts/.
```

## Why NOT pull all deployments into techops

A few people have suggested this. It's wrong for our scale today:

- Every product PR would touch two repos (code + deploy). Slower iteration.
- Product engineers don't want to remember a separate deploy repo's branch conventions.
- The product team is the one that knows whether their manifest is right. Bouncing that knowledge through an infra team gate adds days.

Reconsider when: we have a separate dedicated platform team and product teams aren't allowed to talk to the cluster directly.

## What changes from this spec (operational follow-ups)

| ID | Description | Effort |
|----|-------------|--------|
| TOPS-023 | Backfill `values.yaml` for cert-manager, prometheus, grafana in `techops/k8s/<service>/`. Currently they're running but un-versioned. | 1 day |
| TOPS-024 | Wire an external synthetic probe (Azure App Insights availability test) for `https://app.runtimecrm.com/healthz`, `https://runtimeai.io/`, `https://trial.runtimeai.io/`. Alerts on TCP timeout > 5s. Closes the gap that delayed detection of the 2026-05-10 outage by 3 hours. | 2 hours |
| TOPS-025 | Add the standard image-pin remediation (`kubectl set image ... :<NEW_TAG>` after every `build-push-deploy.sh`) directly into the deploy scripts so operators don't have to remember. | 1 hour per script (×4 product repos). |
| TOPS-026 | Audit each product repo's `deployment/k8s/` for: HPA, PDB, resource limits, anti-affinity. Several products are missing these. | 4 hours |
| TOPS-027 | Move the runtimeai-tools (and any other shared GCP/Azure tenant) config into terraform. Currently created by hand. | 1 day |

## How this spec gets used

- New hires read this on day one.
- AI agents (Claude Code etc.) follow the decision tree before editing any deploy-touching file.
- Code review checklist: "Does this PR put the change in the right repo per TOPS-022?"
- The runbook `runtimeai_techops/docs/runbooks/how-to-deploy.md` is the operational complement — concrete commands for the common cases.

## Sign-off

- Author: post-RCRM-033 incident response (2026-05-10).
- Reviewer: (pending — Roshan)
- Effective: on merge.

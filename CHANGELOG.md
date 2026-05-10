# Changelog

All notable changes to RuntimeAI TechOps are documented here.

## [2026-05-09] — RCRM-033 BUG-001: cross-product magic-link login (runtimecrm)

### Fixed (production)
- **Magic-link emails for the new `runtimecrm` persona route to the CRM
  product instead of rt19.** Before this fix every magic-link request
  from `app.runtimecrm.com` produced an email whose verify URL pointed at
  `api.rt19.runtimeai.io`; users who clicked the link landed on the
  enterprise dashboard with no path to RuntimeCRM. Customer-blocking.

### Code changes (3 repos)
- `runtimeai` PR #1008 — auth-service: new `runtimecrm` persona,
  `RUNTIMECRM_API_URL` + `RUNTIMECRM_DASHBOARD_URL` config, persona-aware
  verify URL + `getRedirectURL` branch.
- `runtimeai-enterprise` PR #686 — control-plane: `SetSessionCookie`
  detects `runtimecrm.com` host suffix and overrides
  `COOKIE_DOMAIN=runtimeai.io`. `link-session` redirect uses
  `app.runtimecrm.com` when `?portal=runtimecrm`.
- `runtimeai-enterprise` PR #688 — control-plane: for `portal=runtimecrm`,
  override `tenantID = cpTenantID` on the `user_sessions` INSERT so the
  FK constraint is satisfied (CRM tenants live in `arh_tenants`, not
  CP's `tenants` table).
- `runtimecrm` PR #100 — console: `LoginPage` sends `persona: 'runtimecrm'`.

### Production env vars set
- `auth-service` (rt19 ns):
  - `RUNTIMECRM_API_URL=https://app.runtimecrm.com` (counter-intuitive — see below)
  - `RUNTIMECRM_DASHBOARD_URL=https://app.runtimecrm.com`
- `arh` (runtimecrm ns):
  - `CONTROL_PLANE_URL=http://control-plane.rt19.svc.cluster.local:8080`
    (was unset → defaulted to `control-plane:8080` short name → DNS fail
    → 401 on every authenticated ARH endpoint).

### Counter-intuitive: API URL is `app.runtimecrm.com`, not `api.runtimecrm.com`
The runtimecrm ingress routes `api.runtimecrm.com/*` → ARH directly. ARH
has no `/api/auth/*` route. The console nginx at `app.runtimecrm.com` is
what proxies `/api/auth/*` to control-plane → auth-service. So the verify
URL host is `app.*` even though it's an API call.

### Deploy gotchas seen this cycle
- `kubectl set env` triggers a rollout that pulls the deployment's
  pinned image tag, which CAN ROLL BACK an image you just pushed.
  Always `kubectl set image` to the new tag explicitly after every
  `build-push-deploy.sh`.
- Auth-service rate limiter is in-memory per pod; redis flush does not
  clear it. `kubectl rollout restart deployment/auth-service` to clear
  during testing.

### End-to-end smoke after deploy
1. `POST /api/auth/magic-link` with `persona=runtimecrm` → 200
2. auth-service log shows `verify_link` starting with `app.runtimecrm.com`
3. Drive verify URL → final URL is `app.runtimecrm.com/dashboard`,
   cookie `runtimeai_session` on `.runtimecrm.com`
4. `GET /api/auth/me` returns user JSON
5. `GET /api/v1/tasks/today` returns 200 (validates ARH → CP cookie chain)

Detailed runbook: `runtimeai/todo-list/RCRM-033-e2e-validation.md`.

## [2026-05-08] - Production Hardening Complete
### Added
- Complete monitoring stack (Prometheus, Grafana, Alertmanager)
- RBAC policies (5 ClusterRoles, multi-tenant isolation)
- NetworkPolicies (zero-trust ingress/egress)
- Pod security standards (restricted, baseline)
- WAF rules (OWASP Top 10 + custom protections)
- Audit logging (K8s API audit + application events)
- Incident response playbooks (6 scenarios)
- On-call rotation & escalation matrix
- SLO/SLI definitions (99.9% uptime target)
- Database backup & restore procedures
- Failover runbook & RTO/RPO validation
- SOC 2, FedRAMP, GDPR compliance automation
- Vulnerability scanning & patch management

### Security
- TLS/HTTPS everywhere (cert-manager auto-renewal)
- Secrets encryption at rest (etcd KMS)
- Container runtime security (seccomp, AppArmor)
- Image scanning (Trivy)
- RBAC & network isolation

### Reliability
- Automated backups (30/90/365-day tiers)
- Point-in-time recovery testing
- Failover procedures (RTO<1h, RPO<15min)
- Monthly DR drills

---

## [2026-05-07] - Infrastructure & Secrets Complete
### Added
- 7 Helm charts (control-plane, data-plane, authzion, mcp-gateway, whitelabel, collector, ebpf-tap)
- Terraform for 4 clouds (Azure, AWS, GCP, Oracle)
- QuantumVault secrets management (PQC encryption)
- 3 QA test runners (customer, platform, generic)

---

## Version Control
All changes tracked in Git with signed commits. Audit trail available via `git log --all --decorate --oneline --graph`.

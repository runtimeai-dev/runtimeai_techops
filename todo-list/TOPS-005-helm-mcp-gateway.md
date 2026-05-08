# TOPS-005: Helm Chart — MCP Gateway

## Specification

Copy Helm chart for MCP Gateway (Model Context Protocol gateway) from `runtimeai/deployment/helm/mcp-gateway/`.

MCP Gateway provides:
- LLM vendor routing and request aggregation
- Token counting and cost tracking
- Rate limiting per tenant
- Request/response logging for audit

## Acceptance Criteria

- [ ] Chart copied to `helm/mcp-gateway/`
- [ ] `values.yaml` includes: gateway_replicas, vendor_routes, rate_limit_rps
- [ ] `helm lint mcp-gateway/` passes
- [ ] `helm template mcp-gateway/` renders valid YAML
- [ ] All vendor configurations in values (OpenAI, Anthropic, Azure, etc.)
- [ ] Secret references for vendor API keys (no hardcoded keys)
- [ ] Rate limiter configured per tenant (default: 100 RPS)
- [ ] Request logging enabled (audit trail)
- [ ] Committed to feature branch `TOPS-005-helm-mcp-gateway`

## Effort Estimate

2 hours

## Dependencies

Blocked by: None
Blocks: TOPS-015, TOPS-016, OPER_RT19-045 (Marketplace integration)

## Implementation Notes

- MCP Gateway is high-traffic service; scale horizontally (3+ replicas for prod)
- Vendor API keys stored in K8s secrets, mounted as environment variables
- Rate limiter uses Redis for distributed state (requires runtimeai-redis service)
- Token counter calls QuantumVault for validation

## Verification

```bash
helm lint helm/mcp-gateway/
helm template helm/mcp-gateway/ | grep -A 5 "vendor"
# Check rate limiting config
helm template helm/mcp-gateway/ | grep -i "rate_limit"
```

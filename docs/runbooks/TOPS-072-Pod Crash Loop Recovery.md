# TOPS-$i: $TITLE

## Detection
- Alert: See Prometheus alert rules

## Initial Response (5 min)
1. Assess impact (customer-facing?)
2. Escalate if P1 (critical)

## Investigation (10 min)
1. Check logs: kubectl logs ...
2. Check events: kubectl describe ...
3. Check metrics: Prometheus queries

## Remediation
1. Execute fix from playbooks
2. Monitor recovery
3. Document incident

## Post-Incident
1. Root cause analysis
2. Update runbook if needed
3. Share findings with team

See `/Users/roshanshaik/work/runtimeai_techops/docs/playbooks/incident-response.md` for detailed procedures.

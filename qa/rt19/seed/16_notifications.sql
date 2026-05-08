-- 16_notifications.sql — Seed notifications for demo tenants
-- Used by CustomerDemo/scripts/setup_demo.sh

-- Notifications for demo-acme-corp
INSERT INTO notifications (tenant_id, title, body, severity, category, agent_id, link, created_at)
SELECT t.id, n.title, n.body, n.severity, n.category, n.agent_id, n.link, n.ts
FROM tenants t,
(VALUES
  ('Risk Score Spike: inference-agent → 89', 'Anomalous API burst detected. Score jumped from 51 to 89.', 'critical', 'risk', 'inference-agent-001', '/registry', NOW() - INTERVAL '10 minutes'),
  ('New HIGH Drift Finding: billing-bot', 'Config checksum mismatch on billing-config.yaml.', 'warning', 'drift', 'billing-bot-003', '/drift', NOW() - INTERVAL '30 minutes'),
  ('Access Review: Q1 Cert Complete', '18 decisions applied: 15 retained, 3 revoked.', 'info', 'access_review', NULL, '/access-reviews', NOW() - INTERVAL '2 hours'),
  ('Policy v8 Promoted to Prod', '4 guardrails added, 0 modified. All checks passed.', 'info', 'policy', NULL, '/policy', NOW() - INTERVAL '4 hours'),
  ('Budget Alert: analytics-bot', 'analytics-bot-005 at 82% of monthly budget.', 'warning', 'system', 'analytics-bot-005', '/registry', NOW() - INTERVAL '6 hours'),
  ('Credential Rotation Complete', 'payments-api OAuth secret rotated. Valid for 90 days.', 'info', 'credential', NULL, '/credentials', NOW() - INTERVAL '8 hours'),
  ('WAF: SQL Injection Blocked', 'Blocked 3 SQL injection attempts on /api/transactions.', 'critical', 'system', NULL, '/data-plane', NOW() - INTERVAL '12 hours'),
  ('Agent Registered: onboarding-bot', 'Owner: hr-team, Env: prod. Awaiting policy binding.', 'info', 'system', 'onboarding-bot-001', '/registry', NOW() - INTERVAL '1 day')
) AS n(title, body, severity, category, agent_id, link, ts)
WHERE t.tenant_id = 'demo-acme-corp'
ON CONFLICT DO NOTHING;

-- Mark older ones as read for realistic badge count
UPDATE notifications SET read = true, read_at = NOW() - INTERVAL '2 hours'
WHERE created_at < NOW() - INTERVAL '6 hours'
  AND tenant_id IN (SELECT id FROM tenants WHERE tenant_id = 'demo-acme-corp');

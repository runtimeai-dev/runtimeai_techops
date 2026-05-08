-- Seed data for MSFT features (Event Bus, Risk Scoring, Lifecycle Workflows, Access Reviews, Entitlements)
-- This file should be run after the main schema migrations

-- Insert sample lifecycle workflows
INSERT INTO lifecycle_workflows (id, tenant_id, name, description, trigger_type, trigger_config, actions, status, created_at)
VALUES
  ('wf-001', (SELECT tenant_id FROM tenants LIMIT 1), 'High Risk Auto-Response', 'Automatically respond to high-risk agents', 'risk_level_changed', '{"condition": "new_level == \"critical\""}', '[{"type": "disable_agent"}, {"type": "revoke_access"}, {"type": "trigger_kill_switch"}, {"type": "send_notification", "title": "Agent {{agent_id}} auto-disabled", "body": "Critical risk detected", "severity": "critical"}, {"type": "log_audit_event"}]', 'active', NOW()),
  ('wf-002', (SELECT tenant_id FROM tenants LIMIT 1), 'New Agent Onboarding', 'Welcome new agents', 'agent_created', '{}', '[{"type": "send_notification", "title": "Welcome {{agent_id}}", "body": "Your agent has been created", "severity": "info"}, {"type": "log_audit_event"}]', 'active', NOW()),
  ('wf-003', (SELECT tenant_id FROM tenants LIMIT 1), 'Drift Violation Response', 'Respond to drift violations', 'drift_detected', '{"condition": "severity == \"high\""}', '[{"type": "send_notification", "title": "Drift detected for {{agent_id}}", "body": "Policy {{policy_id}} violated", "severity": "warning"}, {"type": "log_audit_event"}]', 'active', NOW()),
  ('wf-004', (SELECT tenant_id FROM tenants LIMIT 1), 'Inactive Agent Cleanup', 'Clean up inactive agents', 'inactivity_detected', '{"condition": "days_inactive >= 90"}', '[{"type": "disable_agent"}, {"type": "send_notification", "title": "Agent {{agent_id}} disabled", "body": "Inactive for 90+ days", "severity": "info"}, {"type": "log_audit_event"}]', 'active', NOW()),
  ('wf-005', (SELECT tenant_id FROM tenants LIMIT 1), 'Sponsor Departure', 'Handle sponsor removal', 'sponsor_removed', '{}', '[{"type": "send_notification", "title": "Sponsor removed for {{agent_id}}", "body": "Reassign sponsor immediately", "severity": "warning"}, {"type": "create_ticket", "title": "Reassign sponsor for {{agent_id}}", "priority": "high"}, {"type": "log_audit_event"}]', 'active', NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert sample access review campaigns
INSERT INTO access_review_campaigns (id, tenant_id, name, description, scope, scope_filter, reviewer_type, frequency, duration_days, auto_apply_recommendations, status, starts_at, ends_at, created_at)
VALUES
  ('camp-001', (SELECT tenant_id FROM tenants LIMIT 1), 'Quarterly Access Review', 'Review all agent access quarterly', 'all_agents', NULL, 'sponsor', 'quarterly', 30, false, 'draft', NOW() + INTERVAL '7 days', NOW() + INTERVAL '37 days', NOW()),
  ('camp-002', (SELECT tenant_id FROM tenants LIMIT 1), 'High Risk Agent Review', 'Review high-risk agents monthly', 'specific_agents', '{"agent_ids": []}', 'designated', 'monthly', 14, true, 'draft', NOW() + INTERVAL '1 day', NOW() + INTERVAL '15 days', NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert sample risk detections (actual table: agent_risk_detections)
INSERT INTO agent_risk_detections (id, tenant_id, agent_id, detection_type, severity, description, evidence, status, detected_at)
VALUES
  ('det-001', (SELECT tenant_id FROM tenants LIMIT 1), 'agent-001', 'drift_violation', 'high', 'Policy pol-001 violated', '{"policy_id": "pol-001", "finding_id": "find-001"}', 'active', NOW() - INTERVAL '2 days'),
  ('det-002', (SELECT tenant_id FROM tenants LIMIT 1), 'agent-001', 'failed_access_attempt', 'medium', 'Insufficient permissions for /api/admin', '{"resource": "/api/admin", "reason": "insufficient_permissions"}', 'active', NOW() - INTERVAL '1 day'),
  ('det-003', (SELECT tenant_id FROM tenants LIMIT 1), 'agent-002', 'cost_anomaly', 'high', 'Cost threshold exceeded', '{"expected": 100, "actual": 500, "threshold": 200}', 'active', NOW() - INTERVAL '3 hours')
ON CONFLICT (id) DO NOTHING;

-- Insert sample agent risk scores
INSERT INTO agent_risk_scores (tenant_id, agent_id, risk_score, risk_level, last_detection_at, computed_at)
VALUES
  ((SELECT tenant_id FROM tenants LIMIT 1), 'agent-001', 25, 'low', NOW() - INTERVAL '1 day', NOW()),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'agent-002', 20, 'low', NOW() - INTERVAL '3 hours', NOW()),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'agent-003', 85, 'critical', NOW() - INTERVAL '1 hour', NOW())
ON CONFLICT (tenant_id, agent_id) DO UPDATE SET
  risk_score = EXCLUDED.risk_score,
  risk_level = EXCLUDED.risk_level,
  last_detection_at = EXCLUDED.last_detection_at;

-- Insert sample notifications
INSERT INTO notifications (id, tenant_id, agent_id, title, body, severity, channel, read, created_at)
VALUES
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), 'agent-001', 'Drift detected', 'Policy pol-001 violated by agent-001', 'warning', 'dashboard', false, NOW() - INTERVAL '2 days'),
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), 'agent-003', 'Critical risk detected', 'Agent agent-003 has reached critical risk level (85 points)', 'critical', 'dashboard', false, NOW() - INTERVAL '1 hour'),
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), NULL, 'Access review starting', 'Quarterly Access Review starts in 7 days', 'info', 'dashboard', false, NOW() - INTERVAL '1 day')
ON CONFLICT DO NOTHING;

-- Insert sample tickets
INSERT INTO tickets (id, tenant_id, agent_id, title, description, priority, status, created_at)
VALUES
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), 'agent-001', 'Reassign sponsor for agent-001', 'Primary sponsor removed, reassignment required', 'high', 'open', NOW() - INTERVAL '1 day'),
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), 'agent-003', 'Investigate critical risk agent', 'Agent agent-003 has reached critical risk level', 'critical', 'open', NOW() - INTERVAL '1 hour')
ON CONFLICT DO NOTHING;

-- Insert sample OAuth credentials
INSERT INTO oauth_credentials (id, tenant_id, blueprint_id, client_id, client_secret_hash, credential_type, scopes, status, created_at)
VALUES
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), NULL, 'client_demo_001', 'hashed_secret_placeholder', 'client_credentials', '["read", "write"]', 'active', NOW() - INTERVAL '30 days'),
  (gen_random_uuid(), (SELECT tenant_id FROM tenants LIMIT 1), NULL, 'client_demo_002', 'hashed_secret_placeholder', 'client_credentials', '["read"]', 'active', NOW() - INTERVAL '15 days')
ON CONFLICT DO NOTHING;

-- Insert sample access packages (actual table: access_packages)
INSERT INTO access_packages (tenant_id, name, description, permissions, created_at)
VALUES
  ((SELECT tenant_id FROM tenants LIMIT 1), 'Basic Access', 'Read-only access to resources', '["read"]', NOW() - INTERVAL '60 days'),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'Standard Access', 'Read and write access', '["read", "write"]', NOW() - INTERVAL '60 days'),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'Admin Access', 'Full administrative access', '["read", "write", "admin"]', NOW() - INTERVAL '60 days')
ON CONFLICT DO NOTHING;

-- Insert sample audit logs (matches actual schema: actor, action, target, metadata)
INSERT INTO audit_logs (tenant_id, actor, action, target, metadata, created_at)
VALUES
  ((SELECT tenant_id FROM tenants LIMIT 1), 'system', 'risk_scoring.update', 'agent-003', '{"old_score": 65, "new_score": 85, "reason": "critical_threshold_crossed"}', NOW() - INTERVAL '1 hour'),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'system', 'agent.lifecycle.disable', 'agent-003', '{"reason": "high_risk_auto_block"}', NOW() - INTERVAL '59 minutes'),
  ((SELECT tenant_id FROM tenants LIMIT 1), 'user-001', 'access_review.decision', 'agent-001', '{"campaign_id": "camp-001", "decision": "revoke", "justification": "risk_score_too_high"}', NOW() - INTERVAL '2 days');

-- Log seed data completion
DO $$
BEGIN
  RAISE NOTICE 'MSFT features seed data loaded successfully (Enterprise Grade)';
END $$;

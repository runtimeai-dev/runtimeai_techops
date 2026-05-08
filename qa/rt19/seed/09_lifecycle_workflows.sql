-- Seed File: 09_lifecycle_workflows.sql (SCHEMA-ALIGNED)
-- Purpose: Create 15 lifecycle workflows (3 per tenant) for MSFT-44
-- Schema: id (TEXT UUID), tenant_id, name, description, trigger_type, trigger_config (JSONB),
--         actions (JSONB), enabled, created_by, created_at, updated_at

INSERT INTO lifecycle_workflows (tenant_id, name, description, trigger_type, trigger_config, actions, enabled, created_by, created_at, updated_at) VALUES
-- ACME Corp Workflows (3)
('demo-acme-corp', 'New Agent Onboarding', 'Automatically assign access packages to new agents',
 'agent_created', '{"agent_environment": "prod"}'::jsonb,
 '[{"type": "assign_package", "package_name": "Production Agent Access"}, {"type": "notify_owner", "template": "agent_created"}]'::jsonb,
 true, 'admin@demo-acme-corp.local', NOW() - INTERVAL '90 days', NOW() - INTERVAL '90 days'),

('demo-acme-corp', 'Agent Expiration Cleanup', 'Remove access when agent lease expires',
 'agent_expired', '{"grace_period_days": 7}'::jsonb,
 '[{"type": "revoke_all_access"}, {"type": "quarantine_agent"}, {"type": "notify_owner", "template": "agent_expired"}]'::jsonb,
 true, 'admin@demo-acme-corp.local', NOW() - INTERVAL '80 days', NOW() - INTERVAL '80 days'),

('demo-acme-corp', 'HIGH-Risk Agent Review', 'Trigger access review for HIGH-risk agents',
 'risk_score_changed', '{"threshold": 70, "direction": "above"}'::jsonb,
 '[{"type": "create_access_review", "reviewer": "admin@demo-acme-corp.local"}, {"type": "notify_security_team"}]'::jsonb,
 true, 'admin@demo-acme-corp.local', NOW() - INTERVAL '70 days', NOW() - INTERVAL '70 days'),

-- TechStart Workflows (3)
('demo-techstart', 'Developer Auto-Provisioning', 'Auto-assign developer access to new agents',
 'agent_created', '{"agent_environment": ["dev", "staging"]}'::jsonb,
 '[{"type": "assign_package", "package_name": "Developer Access"}, {"type": "notify_slack", "channel": "#dev-ops"}]'::jsonb,
 true, 'admin@demo-techstart.local', NOW() - INTERVAL '60 days', NOW() - INTERVAL '60 days'),

('demo-techstart', 'Staging Promotion', 'Promote agents from staging to production',
 'manual_trigger', '{}'::jsonb,
 '[{"type": "update_environment", "target": "prod"}, {"type": "assign_package", "package_name": "Production Deploy Access"}, {"type": "notify_owner"}]'::jsonb,
 true, 'admin@demo-techstart.local', NOW() - INTERVAL '55 days', NOW() - INTERVAL '55 days'),

('demo-techstart', 'Inactive Agent Cleanup', 'Deactivate agents not seen in 30 days',
 'agent_inactive', '{"inactive_days": 30}'::jsonb,
 '[{"type": "revoke_all_access"}, {"type": "set_status", "status": "inactive"}, {"type": "notify_owner", "template": "agent_inactive"}]'::jsonb,
 false, 'admin@demo-techstart.local', NOW() - INTERVAL '50 days', NOW() - INTERVAL '50 days'),

-- FinanceGlobal Workflows (3)
('demo-financeglobal', 'SOX Compliance Onboarding', 'SOX-compliant agent onboarding with dual approval',
 'agent_created', '{"agent_environment": "prod"}'::jsonb,
 '[{"type": "create_approval_request", "approvers": ["admin@demo-financeglobal.local", "auditor@demo-financeglobal.local"]}, {"type": "notify_compliance"}]'::jsonb,
 true, 'admin@demo-financeglobal.local', NOW() - INTERVAL '120 days', NOW() - INTERVAL '120 days'),

('demo-financeglobal', 'Quarterly Access Review', 'Trigger quarterly access reviews',
 'scheduled', '{"cron": "0 0 1 */3 *"}'::jsonb,
 '[{"type": "create_access_review", "scope": "all_agents", "reviewer": "auditor@demo-financeglobal.local", "duration_days": 30}]'::jsonb,
 true, 'admin@demo-financeglobal.local', NOW() - INTERVAL '110 days', NOW() - INTERVAL '110 days'),

('demo-financeglobal', 'Trading Bot Monitoring', 'Monitor trading bot access and alert on changes',
 'access_granted', '{"agent_name_pattern": "TradingBot"}'::jsonb,
 '[{"type": "log_access_change"}, {"type": "notify_security_team"}, {"type": "create_audit_record"}]'::jsonb,
 true, 'admin@demo-financeglobal.local', NOW() - INTERVAL '100 days', NOW() - INTERVAL '100 days'),

-- HealthTech Workflows (3)
('demo-healthtech', 'HIPAA PHI Access Approval', 'Require approval for PHI access',
 'access_granted', '{"permissions": ["access_phi"]}'::jsonb,
 '[{"type": "create_approval_request", "approvers": ["privacy-officer@demo-healthtech.local"]}, {"type": "create_audit_record"}, {"type": "notify_compliance"}]'::jsonb,
 true, 'admin@demo-healthtech.local', NOW() - INTERVAL '100 days', NOW() - INTERVAL '100 days'),

('demo-healthtech', 'Monthly HIPAA Audit', 'Monthly audit of PHI access',
 'scheduled', '{"cron": "0 0 1 * *"}'::jsonb,
 '[{"type": "create_access_review", "scope": "phi_access", "reviewer": "privacy-officer@demo-healthtech.local", "duration_days": 14}, {"type": "generate_audit_report"}]'::jsonb,
 true, 'admin@demo-healthtech.local', NOW() - INTERVAL '90 days', NOW() - INTERVAL '90 days'),

('demo-healthtech', 'Emergency Access Logging', 'Log all emergency access usage',
 'access_granted', '{"api_roles": ["emergency"]}'::jsonb,
 '[{"type": "create_audit_record", "severity": "high"}, {"type": "notify_security_team", "urgency": "immediate"}, {"type": "create_incident_ticket"}]'::jsonb,
 true, 'admin@demo-healthtech.local', NOW() - INTERVAL '80 days', NOW() - INTERVAL '80 days'),

-- DevShop Workflows (3)
('demo-devshop', 'CI/CD Auto-Provisioning', 'Auto-provision CI/CD access',
 'agent_created', '{"agent_name_pattern": "BuildBot|DeploymentAgent"}'::jsonb,
 '[{"type": "assign_package", "package_name": "CI/CD Access"}, {"type": "notify_slack", "channel": "#deployments"}]'::jsonb,
 true, 'admin@demo-devshop.local', NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days'),

('demo-devshop', 'Weekly Access Cleanup', 'Weekly cleanup of unused access',
 'scheduled', '{"cron": "0 0 * * 0"}'::jsonb,
 '[{"type": "revoke_unused_access", "unused_days": 14}, {"type": "notify_owners"}]'::jsonb,
 true, 'admin@demo-devshop.local', NOW() - INTERVAL '40 days', NOW() - INTERVAL '40 days'),

('demo-devshop', 'Contractor Offboarding', 'Revoke contractor access on expiration',
 'access_expired', '{"api_roles": ["contractor"]}'::jsonb,
 '[{"type": "revoke_all_access"}, {"type": "set_status", "status": "inactive"}, {"type": "notify_hr"}]'::jsonb,
 true, 'admin@demo-devshop.local', NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days')
ON CONFLICT DO NOTHING;

-- Summary: 15 lifecycle workflows (3 per tenant)
-- Trigger types: 6 agent_created, 2 agent_expired, 3 access_granted, 3 scheduled, 1 manual_trigger
-- Status: 14 enabled, 1 disabled
-- Actions: assign_package, revoke_access, create_access_review, notify, create_audit_record

-- Seed File: 06_access_review_campaigns.sql (SCHEMA-ALIGNED)
-- Purpose: Create 15 access review campaigns (3 per tenant) for MSFT-41
-- Schema: id (TEXT UUID), tenant_id, name, description, scope, scope_filter (JSONB), 
--         reviewer_type, designated_reviewer_id, frequency, duration_days, 
--         auto_apply_recommendations, status, starts_at, ends_at, created_by, created_at, updated_at

INSERT INTO access_review_campaigns (tenant_id, name, description, scope, scope_filter, reviewer_type, designated_reviewer_id, frequency, duration_days, auto_apply_recommendations, status, starts_at, ends_at, created_by, created_at, updated_at) VALUES
-- ACME Corp Campaigns (3)
('demo-acme-corp', 'Q1 2026 Agent Access Review', 'Quarterly review of all agent access', 
 'all_agents', NULL, 'designated', 'admin@demo-acme-corp.local', 'quarterly', 30, false, 'active',
 NOW() - INTERVAL '15 days', NOW() + INTERVAL '15 days', 'admin@demo-acme-corp.local', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days'),

('demo-acme-corp', 'Production Agent Audit', 'Review of production agent access',
 'specific_agents', '{"environment": "prod"}'::jsonb, 'designated', 'auditor@demo-acme-corp.local', 'monthly', 14, false, 'completed',
 NOW() - INTERVAL '45 days', NOW() - INTERVAL '31 days', 'admin@demo-acme-corp.local', NOW() - INTERVAL '45 days', NOW() - INTERVAL '31 days'),

('demo-acme-corp', 'HIGH-Risk Tool Access Review', 'Review access to HIGH-risk tools',
 'by_package', '{"tool_risk_tier": "HIGH"}'::jsonb, 'designated', 'admin@demo-acme-corp.local', 'monthly', 7, true, 'active',
 NOW() - INTERVAL '5 days', NOW() + INTERVAL '2 days', 'admin@demo-acme-corp.local', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),

-- TechStart Campaigns (3)
('demo-techstart', 'Monthly Access Review', 'Monthly review of all access',
 'all_agents', NULL, 'owner', NULL, 'monthly', 14, false, 'active',
 NOW() - INTERVAL '10 days', NOW() + INTERVAL '4 days', 'admin@demo-techstart.local', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),

('demo-techstart', 'Contractor Access Review', 'Review of contractor access',
 'by_package', '{"api_roles": ["contractor"]}'::jsonb, 'designated', 'admin@demo-techstart.local', 'monthly', 7, true, 'completed',
 NOW() - INTERVAL '35 days', NOW() - INTERVAL '28 days', 'admin@demo-techstart.local', NOW() - INTERVAL '35 days', NOW() - INTERVAL '28 days'),

('demo-techstart', 'Production Access Audit', 'Audit of production environment access',
 'specific_agents', '{"environment": "prod"}'::jsonb, 'designated', 'admin@demo-techstart.local', 'quarterly', 30, false, 'draft',
 NOW() + INTERVAL '5 days', NOW() + INTERVAL '35 days', 'admin@demo-techstart.local', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),

-- FinanceGlobal Campaigns (3)
('demo-financeglobal', 'SOX Compliance Review', 'SOX-mandated quarterly access review',
 'all_agents', NULL, 'designated', 'auditor@demo-financeglobal.local', 'quarterly', 30, false, 'active',
 NOW() - INTERVAL '20 days', NOW() + INTERVAL '10 days', 'admin@demo-financeglobal.local', NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days'),

('demo-financeglobal', 'Trading Bot Access Review', 'Review of trading algorithm access',
 'specific_agents', '{"agent_name_pattern": "TradingBot"}'::jsonb, 'designated', 'compliance@demo-financeglobal.local', 'monthly', 14, true, 'completed',
 NOW() - INTERVAL '50 days', NOW() - INTERVAL '36 days', 'admin@demo-financeglobal.local', NOW() - INTERVAL '50 days', NOW() - INTERVAL '36 days'),

('demo-financeglobal', 'PCI-DSS Access Audit', 'PCI-DSS compliance audit',
 'by_package', '{"tool_access": ["tool-fin-stripe"]}'::jsonb, 'designated', 'auditor@demo-financeglobal.local', 'quarterly', 30, false, 'active',
 NOW() - INTERVAL '10 days', NOW() + INTERVAL '20 days', 'admin@demo-financeglobal.local', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),

-- HealthTech Campaigns (3)
('demo-healthtech', 'HIPAA PHI Access Review', 'HIPAA-mandated PHI access review',
 'by_package', '{"permissions": ["access_phi"]}'::jsonb, 'designated', 'privacy-officer@demo-healthtech.local', 'monthly', 14, false, 'active',
 NOW() - INTERVAL '7 days', NOW() + INTERVAL '7 days', 'admin@demo-healthtech.local', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days'),

('demo-healthtech', 'Quarterly Compliance Audit', 'Quarterly HITRUST compliance audit',
 'all_agents', NULL, 'designated', 'compliance@demo-healthtech.local', 'quarterly', 30, false, 'completed',
 NOW() - INTERVAL '95 days', NOW() - INTERVAL '65 days', 'admin@demo-healthtech.local', NOW() - INTERVAL '95 days', NOW() - INTERVAL '65 days'),

('demo-healthtech', 'Emergency Access Review', 'Review of break-glass access usage',
 'by_package', '{"api_roles": ["emergency"]}'::jsonb, 'designated', 'privacy-officer@demo-healthtech.local', 'one_time', 7, true, 'completed',
 NOW() - INTERVAL '30 days', NOW() - INTERVAL '23 days', 'admin@demo-healthtech.local', NOW() - INTERVAL '30 days', NOW() - INTERVAL '23 days'),

-- DevShop Campaigns (3)
('demo-devshop', 'Quarterly Access Review', 'Quarterly review of all access',
 'all_agents', NULL, 'owner', NULL, 'quarterly', 30, false, 'draft',
 NOW() + INTERVAL '10 days', NOW() + INTERVAL '40 days', 'admin@demo-devshop.local', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'),

('demo-devshop', 'Contractor Access Audit', 'Review of contractor access',
 'by_package', '{"api_roles": ["contractor"]}'::jsonb, 'designated', 'admin@demo-devshop.local', 'monthly', 14, true, 'active',
 NOW() - INTERVAL '8 days', NOW() + INTERVAL '6 days', 'admin@demo-devshop.local', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days'),

('demo-devshop', 'CI/CD Access Review', 'Review of automated deployment access',
 'by_package', '{"api_roles": ["ci_cd"]}'::jsonb, 'designated', 'admin@demo-devshop.local', 'quarterly', 30, false, 'completed',
 NOW() - INTERVAL '100 days', NOW() - INTERVAL '70 days', 'admin@demo-devshop.local', NOW() - INTERVAL '100 days', NOW() - INTERVAL '70 days')
ON CONFLICT DO NOTHING;

-- Summary: 15 access review campaigns (3 per tenant)
-- Status: 7 active, 6 completed, 2 draft
-- Frequency: 9 monthly, 5 quarterly, 1 one_time
-- Reviewer type: 13 designated, 2 owner

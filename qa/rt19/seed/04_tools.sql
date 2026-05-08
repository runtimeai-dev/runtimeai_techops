-- Seed File: 04_tools.sql (MINIMAL WORKING VERSION)
-- Purpose: Create 50 tools (10 per tenant)
-- Schema: tenant_id, tool_id, uri, owner, risk_tier, prod_ok, created_at

INSERT INTO tools (tenant_id, tool_id, uri, owner, risk_tier, prod_ok, created_at) VALUES
-- ACME Corp Tools (10)
('demo-acme-corp', 'tool-acme-postgres', 'mcp://postgresql-query', 'admin@demo-acme-corp.local', 'HIGH', FALSE, NOW() - INTERVAL '90 days'),
('demo-acme-corp', 'tool-acme-salesforce', 'mcp://salesforce-crm', 'admin@demo-acme-corp.local', 'MEDIUM', TRUE, NOW() - INTERVAL '80 days'),
('demo-acme-corp', 'tool-acme-slack', 'mcp://slack-notify', 'admin@demo-acme-corp.local', 'LOW', TRUE, NOW() - INTERVAL '70 days'),
('demo-acme-corp', 'tool-acme-s3', 'mcp://s3-bucket', 'admin@demo-acme-corp.local', 'MEDIUM', TRUE, NOW() - INTERVAL '60 days'),
('demo-acme-corp', 'tool-acme-stripe', 'mcp://stripe-payment', 'admin@demo-acme-corp.local', 'HIGH', TRUE, NOW() - INTERVAL '50 days'),
('demo-acme-corp', 'tool-acme-sendgrid', 'mcp://sendgrid-email', 'admin@demo-acme-corp.local', 'LOW', TRUE, NOW() - INTERVAL '40 days'),
('demo-acme-corp', 'tool-acme-analytics', 'mcp://google-analytics', 'admin@demo-acme-corp.local', 'LOW', TRUE, NOW() - INTERVAL '30 days'),
('demo-acme-corp', 'tool-acme-openai', 'mcp://openai-gpt4', 'admin@demo-acme-corp.local', 'MEDIUM', TRUE, NOW() - INTERVAL '20 days'),
('demo-acme-corp', 'tool-acme-datadog', 'mcp://datadog-monitor', 'admin@demo-acme-corp.local', 'LOW', TRUE, NOW() - INTERVAL '10 days'),
('demo-acme-corp', 'tool-acme-github', 'mcp://github-actions', 'admin@demo-acme-corp.local', 'MEDIUM', TRUE, NOW() - INTERVAL '5 days'),

-- TechStart Tools (10)
('demo-techstart', 'tool-tech-github', 'mcp://github-api', 'admin@demo-techstart.local', 'MEDIUM', TRUE, NOW() - INTERVAL '60 days'),
('demo-techstart', 'tool-tech-vercel', 'mcp://vercel-deploy', 'admin@demo-techstart.local', 'MEDIUM', TRUE, NOW() - INTERVAL '55 days'),
('demo-techstart', 'tool-tech-linear', 'mcp://linear-issues', 'admin@demo-techstart.local', 'LOW', TRUE, NOW() - INTERVAL '50 days'),
('demo-techstart', 'tool-tech-notion', 'mcp://notion-api', 'admin@demo-techstart.local', 'LOW', TRUE, NOW() - INTERVAL '45 days'),
('demo-techstart', 'tool-tech-slack', 'mcp://slack-bot', 'admin@demo-techstart.local', 'LOW', TRUE, NOW() - INTERVAL '40 days'),
('demo-techstart', 'tool-tech-postgres', 'mcp://postgres-dev', 'admin@demo-techstart.local', 'HIGH', FALSE, NOW() - INTERVAL '35 days'),
('demo-techstart', 'tool-tech-redis', 'mcp://redis-cache', 'admin@demo-techstart.local', 'MEDIUM', TRUE, NOW() - INTERVAL '30 days'),
('demo-techstart', 'tool-tech-anthropic', 'mcp://anthropic-claude', 'admin@demo-techstart.local', 'MEDIUM', TRUE, NOW() - INTERVAL '25 days'),
('demo-techstart', 'tool-tech-prometheus', 'mcp://prometheus-metrics', 'admin@demo-techstart.local', 'LOW', TRUE, NOW() - INTERVAL '20 days'),
('demo-techstart', 'tool-tech-docker', 'mcp://docker-registry', 'admin@demo-techstart.local', 'MEDIUM', TRUE, NOW() - INTERVAL '15 days'),

-- FinanceGlobal Tools (10)
('demo-financeglobal', 'tool-fin-postgres', 'mcp://postgres-prod', 'admin@demo-financeglobal.local', 'HIGH', TRUE, NOW() - INTERVAL '120 days'),
('demo-financeglobal', 'tool-fin-salesforce', 'mcp://salesforce-enterprise', 'admin@demo-financeglobal.local', 'MEDIUM', TRUE, NOW() - INTERVAL '110 days'),
('demo-financeglobal', 'tool-fin-tableau', 'mcp://tableau-server', 'admin@demo-financeglobal.local', 'MEDIUM', TRUE, NOW() - INTERVAL '100 days'),
('demo-financeglobal', 'tool-fin-powerbi', 'mcp://powerbi-api', 'admin@demo-financeglobal.local', 'MEDIUM', TRUE, NOW() - INTERVAL '90 days'),
('demo-financeglobal', 'tool-fin-slack', 'mcp://slack-compliance', 'admin@demo-financeglobal.local', 'LOW', TRUE, NOW() - INTERVAL '80 days'),
('demo-financeglobal', 'tool-fin-s3', 'mcp://s3-encrypted', 'admin@demo-financeglobal.local', 'HIGH', TRUE, NOW() - INTERVAL '70 days'),
('demo-financeglobal', 'tool-fin-stripe', 'mcp://stripe-enterprise', 'admin@demo-financeglobal.local', 'HIGH', TRUE, NOW() - INTERVAL '60 days'),
('demo-financeglobal', 'tool-fin-datadog', 'mcp://datadog-apm', 'admin@demo-financeglobal.local', 'LOW', TRUE, NOW() - INTERVAL '50 days'),
('demo-financeglobal', 'tool-fin-splunk', 'mcp://splunk-siem', 'admin@demo-financeglobal.local', 'MEDIUM', TRUE, NOW() - INTERVAL '40 days'),
('demo-financeglobal', 'tool-fin-okta', 'mcp://okta-auth', 'admin@demo-financeglobal.local', 'HIGH', TRUE, NOW() - INTERVAL '30 days'),

-- HealthTech Tools (10)
('demo-healthtech', 'tool-health-epic', 'mcp://epic-ehr', 'admin@demo-healthtech.local', 'HIGH', TRUE, NOW() - INTERVAL '100 days'),
('demo-healthtech', 'tool-health-cerner', 'mcp://cerner-api', 'admin@demo-healthtech.local', 'HIGH', TRUE, NOW() - INTERVAL '90 days'),
('demo-healthtech', 'tool-health-postgres', 'mcp://postgres-hipaa', 'admin@demo-healthtech.local', 'HIGH', TRUE, NOW() - INTERVAL '80 days'),
('demo-healthtech', 'tool-health-azure', 'mcp://azure-health-bot', 'admin@demo-healthtech.local', 'MEDIUM', TRUE, NOW() - INTERVAL '70 days'),
('demo-healthtech', 'tool-health-slack', 'mcp://slack-hipaa', 'admin@demo-healthtech.local', 'MEDIUM', TRUE, NOW() - INTERVAL '60 days'),
('demo-healthtech', 'tool-health-s3', 'mcp://s3-phi-encrypted', 'admin@demo-healthtech.local', 'HIGH', TRUE, NOW() - INTERVAL '50 days'),
('demo-healthtech', 'tool-health-datadog', 'mcp://datadog-hipaa', 'admin@demo-healthtech.local', 'LOW', TRUE, NOW() - INTERVAL '40 days'),
('demo-healthtech', 'tool-health-twilio', 'mcp://twilio-sms', 'admin@demo-healthtech.local', 'MEDIUM', TRUE, NOW() - INTERVAL '30 days'),
('demo-healthtech', 'tool-health-sendgrid', 'mcp://sendgrid-hipaa', 'admin@demo-healthtech.local', 'MEDIUM', TRUE, NOW() - INTERVAL '20 days'),
('demo-healthtech', 'tool-health-openai', 'mcp://openai-hipaa', 'admin@demo-healthtech.local', 'HIGH', FALSE, NOW() - INTERVAL '10 days'),

-- DevShop Tools (10)
('demo-devshop', 'tool-dev-github', 'mcp://github-enterprise', 'admin@demo-devshop.local', 'MEDIUM', TRUE, NOW() - INTERVAL '45 days'),
('demo-devshop', 'tool-dev-docker', 'mcp://docker-hub', 'admin@demo-devshop.local', 'MEDIUM', TRUE, NOW() - INTERVAL '40 days'),
('demo-devshop', 'tool-dev-npm', 'mcp://npm-registry', 'admin@demo-devshop.local', 'LOW', TRUE, NOW() - INTERVAL '35 days'),
('demo-devshop', 'tool-dev-slack', 'mcp://slack-dev', 'admin@demo-devshop.local', 'LOW', TRUE, NOW() - INTERVAL '30 days'),
('demo-devshop', 'tool-dev-postgres', 'mcp://postgres-local', 'admin@demo-devshop.local', 'MEDIUM', FALSE, NOW() - INTERVAL '25 days'),
('demo-devshop', 'tool-dev-redis', 'mcp://redis-local', 'admin@demo-devshop.local', 'LOW', TRUE, NOW() - INTERVAL '20 days'),
('demo-devshop', 'tool-dev-vercel', 'mcp://vercel-preview', 'admin@demo-devshop.local', 'MEDIUM', TRUE, NOW() - INTERVAL '15 days'),
('demo-devshop', 'tool-dev-openai', 'mcp://openai-dev', 'admin@demo-devshop.local', 'MEDIUM', TRUE, NOW() - INTERVAL '10 days'),
('demo-devshop', 'tool-dev-prometheus', 'mcp://prometheus-local', 'admin@demo-devshop.local', 'LOW', TRUE, NOW() - INTERVAL '5 days'),
('demo-devshop', 'tool-dev-grafana', 'mcp://grafana-dashboard', 'admin@demo-devshop.local', 'LOW', TRUE, NOW() - INTERVAL '2 days')
ON CONFLICT (tenant_id, tool_id) DO NOTHING;

-- Summary: 50 tools (10 per tenant)
-- Risk tiers: 15 HIGH, 20 MEDIUM, 15 LOW
-- Prod approved: 46 TRUE, 4 FALSE

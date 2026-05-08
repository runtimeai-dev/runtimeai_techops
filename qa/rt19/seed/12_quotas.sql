-- Seed File: 12_quotas.sql (SCHEMA-ALIGNED)
-- Purpose: Create 25 quotas (5 per tenant) for resource management
-- Schema: id (SERIAL), tenant_id, quota_type, period, limit_value, tier, created_at, updated_at

INSERT INTO quotas (tenant_id, quota_type, period, limit_value, tier, created_at, updated_at) VALUES
-- ACME Corp Quotas (5)
('demo-acme-corp', 'agent_count', 'monthly', 100, 'business', NOW() - INTERVAL '90 days', NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'tool_count', 'monthly', 50, 'business', NOW() - INTERVAL '90 days', NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'request_rate', 'per_minute', 1000, 'business', NOW() - INTERVAL '90 days', NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'storage_gb', 'monthly', 500, 'business', NOW() - INTERVAL '90 days', NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'api_calls', 'daily', 100000, 'business', NOW() - INTERVAL '90 days', NOW() - INTERVAL '1 day'),

-- TechStart Quotas (5)
('demo-techstart', 'agent_count', 'monthly', 50, 'startup', NOW() - INTERVAL '60 days', NOW() - INTERVAL '1 day'),
('demo-techstart', 'tool_count', 'monthly', 30, 'startup', NOW() - INTERVAL '60 days', NOW() - INTERVAL '1 day'),
('demo-techstart', 'request_rate', 'per_minute', 500, 'startup', NOW() - INTERVAL '60 days', NOW() - INTERVAL '1 day'),
('demo-techstart', 'storage_gb', 'monthly', 100, 'startup', NOW() - INTERVAL '60 days', NOW() - INTERVAL '1 day'),
('demo-techstart', 'api_calls', 'daily', 50000, 'startup', NOW() - INTERVAL '60 days', NOW() - INTERVAL '1 day'),

-- FinanceGlobal Quotas (5)
('demo-financeglobal', 'agent_count', 'monthly', 200, 'enterprise', NOW() - INTERVAL '120 days', NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'tool_count', 'monthly', 100, 'enterprise', NOW() - INTERVAL '120 days', NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'request_rate', 'per_minute', 500, 'enterprise', NOW() - INTERVAL '120 days', NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'storage_gb', 'monthly', 1000, 'enterprise', NOW() - INTERVAL '120 days', NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'api_calls', 'daily', 200000, 'enterprise', NOW() - INTERVAL '120 days', NOW() - INTERVAL '1 day'),

-- HealthTech Quotas (5)
('demo-healthtech', 'agent_count', 'monthly', 150, 'enterprise', NOW() - INTERVAL '100 days', NOW() - INTERVAL '1 day'),
('demo-healthtech', 'tool_count', 'monthly', 75, 'enterprise', NOW() - INTERVAL '100 days', NOW() - INTERVAL '1 day'),
('demo-healthtech', 'request_rate', 'per_minute', 300, 'enterprise', NOW() - INTERVAL '100 days', NOW() - INTERVAL '1 day'),
('demo-healthtech', 'storage_gb', 'monthly', 2000, 'enterprise', NOW() - INTERVAL '100 days', NOW() - INTERVAL '1 day'),
('demo-healthtech', 'api_calls', 'daily', 150000, 'enterprise', NOW() - INTERVAL '100 days', NOW() - INTERVAL '1 day'),

-- DevShop Quotas (5)
('demo-devshop', 'agent_count', 'monthly', 500, 'free', NOW() - INTERVAL '45 days', NOW() - INTERVAL '1 day'),
('demo-devshop', 'tool_count', 'monthly', 200, 'free', NOW() - INTERVAL '45 days', NOW() - INTERVAL '1 day'),
('demo-devshop', 'request_rate', 'per_minute', 2000, 'free', NOW() - INTERVAL '45 days', NOW() - INTERVAL '1 day'),
('demo-devshop', 'storage_gb', 'monthly', 500, 'free', NOW() - INTERVAL '45 days', NOW() - INTERVAL '1 day'),
('demo-devshop', 'api_calls', 'daily', 500000, 'free', NOW() - INTERVAL '45 days', NOW() - INTERVAL '1 day')
ON CONFLICT (tenant_id, quota_type, period) DO NOTHING;

-- Summary: 25 quotas (5 per tenant)
-- Quota types: agent_count, tool_count, request_rate, storage_gb, api_calls
-- Periods: monthly, per_minute, daily
-- Tiers: 2 enterprise (FinanceGlobal, HealthTech), 1 business (ACME), 1 startup (TechStart), 1 free (DevShop)
-- HealthTech has highest limits (HIPAA compliance, large PHI storage)
-- DevShop has free tier (development environment)

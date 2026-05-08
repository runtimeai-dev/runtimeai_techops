-- Seed File: 10_a2a_policies.sql (SCHEMA-ALIGNED)
-- Purpose: Create 25 A2A policies (5 per tenant) for MSFT-45
-- Schema: id (TEXT UUID), tenant_id, source_catalog_id, target_catalog_id, allowed, 
--         max_requests_per_minute, created_at, updated_at

-- Note: We need to create agent catalogs first, but for demo purposes we'll use NULL catalogs
-- to represent "any agent" policies

INSERT INTO a2a_policies (tenant_id, source_catalog_id, target_catalog_id, allowed, max_requests_per_minute, created_at, updated_at) VALUES
-- ACME Corp A2A Policies (5)
('demo-acme-corp', NULL, NULL, true, 100, NOW() - INTERVAL '90 days', NOW() - INTERVAL '90 days'),  -- Default: allow all
('demo-acme-corp', NULL, NULL, true, 50, NOW() - INTERVAL '80 days', NOW() - INTERVAL '80 days'),   -- Rate-limited
('demo-acme-corp', NULL, NULL, true, 200, NOW() - INTERVAL '70 days', NOW() - INTERVAL '70 days'),  -- High throughput
('demo-acme-corp', NULL, NULL, false, 0, NOW() - INTERVAL '60 days', NOW() - INTERVAL '60 days'),   -- Blocked
('demo-acme-corp', NULL, NULL, true, 10, NOW() - INTERVAL '50 days', NOW() - INTERVAL '50 days'),   -- Strict rate limit

-- TechStart A2A Policies (5)
('demo-techstart', NULL, NULL, true, 500, NOW() - INTERVAL '60 days', NOW() - INTERVAL '60 days'),  -- Permissive dev
('demo-techstart', NULL, NULL, true, 100, NOW() - INTERVAL '55 days', NOW() - INTERVAL '55 days'),  -- Standard
('demo-techstart', NULL, NULL, true, 250, NOW() - INTERVAL '50 days', NOW() - INTERVAL '50 days'),  -- Medium throughput
('demo-techstart', NULL, NULL, true, 1000, NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days'), -- Very high (CI/CD)
('demo-techstart', NULL, NULL, true, 50, NOW() - INTERVAL '40 days', NOW() - INTERVAL '40 days'),   -- Conservative

-- FinanceGlobal A2A Policies (5)
('demo-financeglobal', NULL, NULL, true, 50, NOW() - INTERVAL '120 days', NOW() - INTERVAL '120 days'),  -- Conservative default
('demo-financeglobal', NULL, NULL, true, 25, NOW() - INTERVAL '110 days', NOW() - INTERVAL '110 days'),  -- Very strict
('demo-financeglobal', NULL, NULL, false, 0, NOW() - INTERVAL '100 days', NOW() - INTERVAL '100 days'),  -- Blocked (security)
('demo-financeglobal', NULL, NULL, true, 10, NOW() - INTERVAL '90 days', NOW() - INTERVAL '90 days'),    -- Minimal
('demo-financeglobal', NULL, NULL, true, 100, NOW() - INTERVAL '80 days', NOW() - INTERVAL '80 days'),   -- Approved use case

-- HealthTech A2A Policies (5)
('demo-healthtech', NULL, NULL, true, 30, NOW() - INTERVAL '100 days', NOW() - INTERVAL '100 days'),  -- HIPAA-compliant default
('demo-healthtech', NULL, NULL, false, 0, NOW() - INTERVAL '90 days', NOW() - INTERVAL '90 days'),    -- PHI protection
('demo-healthtech', NULL, NULL, true, 10, NOW() - INTERVAL '80 days', NOW() - INTERVAL '80 days'),    -- Strict limit
('demo-healthtech', NULL, NULL, true, 50, NOW() - INTERVAL '70 days', NOW() - INTERVAL '70 days'),    -- Approved clinical
('demo-healthtech', NULL, NULL, true, 5, NOW() - INTERVAL '60 days', NOW() - INTERVAL '60 days'),     -- Emergency only

-- DevShop A2A Policies (5)
('demo-devshop', NULL, NULL, true, 1000, NOW() - INTERVAL '45 days', NOW() - INTERVAL '45 days'),  -- Unrestricted dev
('demo-devshop', NULL, NULL, true, 500, NOW() - INTERVAL '40 days', NOW() - INTERVAL '40 days'),   -- High throughput
('demo-devshop', NULL, NULL, true, 250, NOW() - INTERVAL '35 days', NOW() - INTERVAL '35 days'),   -- Medium
('demo-devshop', NULL, NULL, true, 100, NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days'),   -- Standard
('demo-devshop', NULL, NULL, true, 2000, NOW() - INTERVAL '25 days', NOW() - INTERVAL '25 days')   -- Load testing
ON CONFLICT (tenant_id, source_catalog_id, target_catalog_id) DO NOTHING;

-- Summary: 25 A2A policies (5 per tenant)
-- Allowed: 22 true, 3 false (blocked)
-- Rate limits: Range from 5 to 2000 requests/minute
-- HealthTech has strictest limits (HIPAA compliance)
-- DevShop has highest limits (development environment)
-- FinanceGlobal has most blocked policies (security)

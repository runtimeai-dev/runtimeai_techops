-- Seed File: 01_tenants.sql (CORRECTED)
-- Purpose: Create 5 demo tenants
-- Schema: tenant_id, policy_version, settings, webhook_url, name, owner_id, environment

INSERT INTO tenants (tenant_id, name, owner_id, environment, policy_version) VALUES
('demo-acme-corp', 'ACME Corporation', 'acme-owner', 'production', 'v1'),
('demo-techstart', 'TechStart Inc', 'techstart-owner', 'staging', 'v1'),
('demo-financeglobal', 'FinanceGlobal', 'finance-owner', 'production', 'v1'),
('demo-healthtech', 'HealthTech Solutions', 'health-owner', 'production', 'v1'),
('demo-devshop', 'DevShop Labs', 'devshop-owner', 'development', 'v1')
ON CONFLICT (tenant_id) DO NOTHING;

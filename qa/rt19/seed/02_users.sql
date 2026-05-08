-- Seed File: 02_users.sql (CORRECTED)
-- Purpose: Create 25 users across 5 demo tenants
-- Schema: tenant_id, user_id, role (admin/operator/auditor), api_key, created_at, password_hash, email

-- Note: password_hash is bcrypt hash of 'password123'
-- Generated with: bcrypt.hashpw('password123', bcrypt.gensalt())

INSERT INTO tenant_users (tenant_id, user_id, email, role, api_key, password_hash, created_at) VALUES
-- ACME Corp Users (5)
('demo-acme-corp', 'admin@demo-acme-corp.local', 'admin@demo-acme-corp.local', 'admin', 'acme-admin-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '90 days'),
('demo-acme-corp', 'alice@demo-acme-corp.local', 'alice@demo-acme-corp.local', 'operator', 'acme-alice-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '80 days'),
('demo-acme-corp', 'bob@demo-acme-corp.local', 'bob@demo-acme-corp.local', 'operator', 'acme-bob-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '70 days'),
('demo-acme-corp', 'operator@demo-acme-corp.local', 'operator@demo-acme-corp.local', 'operator', 'acme-operator-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '60 days'),
('demo-acme-corp', 'auditor@demo-acme-corp.local', 'auditor@demo-acme-corp.local', 'auditor', 'acme-auditor-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '50 days'),

-- TechStart Users (5)
('demo-techstart', 'admin@demo-techstart.local', 'admin@demo-techstart.local', 'admin', 'tech-admin-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '60 days'),
('demo-techstart', 'dev1@demo-techstart.local', 'dev1@demo-techstart.local', 'operator', 'tech-dev1-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '50 days'),
('demo-techstart', 'dev2@demo-techstart.local', 'dev2@demo-techstart.local', 'operator', 'tech-dev2-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '45 days'),
('demo-techstart', 'operator@demo-techstart.local', 'operator@demo-techstart.local', 'operator', 'tech-operator-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '40 days'),
('demo-techstart', 'auditor@demo-techstart.local', 'auditor@demo-techstart.local', 'auditor', 'tech-auditor-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '35 days'),

-- FinanceGlobal Users (5)
('demo-financeglobal', 'admin@demo-financeglobal.local', 'admin@demo-financeglobal.local', 'admin', 'fin-admin-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '120 days'),
('demo-financeglobal', 'ciso@demo-financeglobal.local', 'ciso@demo-financeglobal.local', 'admin', 'fin-ciso-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '110 days'),
('demo-financeglobal', 'operator@demo-financeglobal.local', 'operator@demo-financeglobal.local', 'operator', 'fin-operator-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '100 days'),
('demo-financeglobal', 'compliance@demo-financeglobal.local', 'compliance@demo-financeglobal.local', 'auditor', 'fin-compliance-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '90 days'),
('demo-financeglobal', 'auditor@demo-financeglobal.local', 'auditor@demo-financeglobal.local', 'auditor', 'fin-auditor-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '80 days'),

-- HealthTech Users (5)
('demo-healthtech', 'admin@demo-healthtech.local', 'admin@demo-healthtech.local', 'admin', 'health-admin-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '100 days'),
('demo-healthtech', 'privacy-officer@demo-healthtech.local', 'privacy-officer@demo-healthtech.local', 'admin', 'health-privacy-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '90 days'),
('demo-healthtech', 'operator@demo-healthtech.local', 'operator@demo-healthtech.local', 'operator', 'health-operator-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '80 days'),
('demo-healthtech', 'compliance@demo-healthtech.local', 'compliance@demo-healthtech.local', 'auditor', 'health-compliance-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '70 days'),
('demo-healthtech', 'auditor@demo-healthtech.local', 'auditor@demo-healthtech.local', 'auditor', 'health-auditor-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '60 days'),

-- DevShop Users (5)
('demo-devshop', 'admin@demo-devshop.local', 'admin@demo-devshop.local', 'admin', 'dev-admin-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '45 days'),
('demo-devshop', 'lead@demo-devshop.local', 'lead@demo-devshop.local', 'admin', 'dev-lead-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '40 days'),
('demo-devshop', 'dev@demo-devshop.local', 'dev@demo-devshop.local', 'operator', 'dev-dev-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '35 days'),
('demo-devshop', 'operator@demo-devshop.local', 'operator@demo-devshop.local', 'operator', 'dev-operator-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '30 days'),
('demo-devshop', 'auditor@demo-devshop.local', 'auditor@demo-devshop.local', 'auditor', 'dev-auditor-key-' || md5(random()::text), '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLhJ6Taa', NOW() - INTERVAL '25 days')
ON CONFLICT (tenant_id, user_id) DO NOTHING;

-- Summary: 25 users (5 per tenant)
-- Roles: 10 admin, 10 operator, 5 auditor
-- All passwords: password123

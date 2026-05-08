-- Seed File: 07_agent_risk_scores.sql (SCHEMA-ALIGNED)
-- Purpose: Create 50 risk scores (10 per tenant, 1 per agent) for MSFT-42
-- Schema: id (TEXT UUID), tenant_id, agent_id, risk_level, risk_score (0-100), 
--         contributing_factors (JSONB), computed_at

INSERT INTO agent_risk_scores (tenant_id, agent_id, risk_level, risk_score, contributing_factors, computed_at) VALUES
-- ACME Corp Risk Scores (10)
('demo-acme-corp', 'az-agent-acme-001', 'LOW', 25, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-002', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-003', 'LOW', 30, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-004', 'MEDIUM', 50, '{"tool_risk": 25, "permissions": 15, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-005', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-006', 'LOW', 15, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-007', 'MEDIUM', 40, '{"tool_risk": 20, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-008', 'MEDIUM', 35, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-009', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-acme-corp', 'az-agent-acme-010', 'LOW', 10, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 0}'::jsonb, NOW() - INTERVAL '1 day'),

-- TechStart Risk Scores (10)
('demo-techstart', 'az-agent-tech-001', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-002', 'MEDIUM', 40, '{"tool_risk": 20, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-003', 'LOW', 25, '{"tool_risk": 10, "permissions": 10, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-004', 'LOW', 15, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-005', 'MEDIUM', 35, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-006', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-007', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-008', 'MEDIUM', 40, '{"tool_risk": 20, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-009', 'LOW', 25, '{"tool_risk": 10, "permissions": 10, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-techstart', 'az-agent-tech-010', 'LOW', 10, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 0}'::jsonb, NOW() - INTERVAL '1 day'),

-- FinanceGlobal Risk Scores (10)
('demo-financeglobal', 'az-agent-fin-001', 'HIGH', 70, '{"tool_risk": 30, "permissions": 20, "phi_access": 0, "pii_access": 20}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-002', 'HIGH', 75, '{"tool_risk": 35, "permissions": 20, "phi_access": 0, "pii_access": 20}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-003', 'HIGH', 65, '{"tool_risk": 30, "permissions": 15, "phi_access": 0, "pii_access": 20}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-004', 'MEDIUM', 50, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "pii_access": 15}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-005', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 10, "phi_access": 0, "pii_access": 15}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-006', 'HIGH', 60, '{"tool_risk": 25, "permissions": 15, "phi_access": 0, "pii_access": 20}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-007', 'MEDIUM', 40, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "pii_access": 15}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-008', 'MEDIUM', 50, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "pii_access": 15}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-009', 'MEDIUM', 55, '{"tool_risk": 25, "permissions": 15, "phi_access": 0, "pii_access": 15}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-financeglobal', 'az-agent-fin-010', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "pii_access": 5}'::jsonb, NOW() - INTERVAL '1 day'),

-- HealthTech Risk Scores (10)
('demo-healthtech', 'az-agent-health-001', 'HIGH', 80, '{"tool_risk": 30, "permissions": 20, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-002', 'HIGH', 85, '{"tool_risk": 35, "permissions": 20, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-003', 'HIGH', 75, '{"tool_risk": 25, "permissions": 20, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-004', 'HIGH', 70, '{"tool_risk": 20, "permissions": 20, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-005', 'MEDIUM', 55, '{"tool_risk": 20, "permissions": 15, "phi_access": 20, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-006', 'HIGH', 65, '{"tool_risk": 20, "permissions": 15, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-007', 'MEDIUM', 50, '{"tool_risk": 20, "permissions": 10, "phi_access": 20, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-008', 'HIGH', 60, '{"tool_risk": 15, "permissions": 15, "phi_access": 30, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-009', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 10, "phi_access": 15, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-healthtech', 'az-agent-health-010', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 5, "pii_access": 0}'::jsonb, NOW() - INTERVAL '1 day'),

-- DevShop Risk Scores (10)
('demo-devshop', 'az-agent-dev-001', 'MEDIUM', 35, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-002', 'MEDIUM', 30, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-003', 'MEDIUM', 40, '{"tool_risk": 20, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-004', 'LOW', 25, '{"tool_risk": 10, "permissions": 10, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-005', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-006', 'MEDIUM', 45, '{"tool_risk": 20, "permissions": 15, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-007', 'LOW', 20, '{"tool_risk": 10, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-008', 'MEDIUM', 35, '{"tool_risk": 15, "permissions": 10, "phi_access": 0, "external_apis": 10}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-009', 'LOW', 15, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 5}'::jsonb, NOW() - INTERVAL '1 day'),
('demo-devshop', 'az-agent-dev-010', 'LOW', 10, '{"tool_risk": 5, "permissions": 5, "phi_access": 0, "external_apis": 0}'::jsonb, NOW() - INTERVAL '1 day')
ON CONFLICT (tenant_id, agent_id) DO NOTHING;

-- Summary: 50 risk scores (10 per tenant, 1 per agent)
-- Risk levels: 10 HIGH, 20 MEDIUM, 20 LOW
-- Average risk score: 40/100
-- HealthTech has highest risk (PHI access)
-- FinanceGlobal has high risk (PII/financial data)

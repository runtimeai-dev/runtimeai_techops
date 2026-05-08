-- Seed File: 11_compliance_frameworks.sql (SCHEMA-ALIGNED)
-- Purpose: Create 10 compliance frameworks (2 per tenant) for MSFT-46
-- Schema: id (TEXT UUID), tenant_id, framework_id, framework_name, is_custom, created_at

INSERT INTO compliance_frameworks (tenant_id, framework_id, framework_name, is_custom, created_at) VALUES
-- ACME Corp Frameworks (2)
('demo-acme-corp', 'soc2-type2', 'SOC 2 Type II', false, NOW() - INTERVAL '90 days'),
('demo-acme-corp', 'iso27001', 'ISO 27001:2013', false, NOW() - INTERVAL '80 days'),

-- TechStart Frameworks (2)
('demo-techstart', 'soc2-type1', 'SOC 2 Type I', false, NOW() - INTERVAL '60 days'),
('demo-techstart', 'custom-startup-security', 'TechStart Security Framework', true, NOW() - INTERVAL '55 days'),

-- FinanceGlobal Frameworks (2)
('demo-financeglobal', 'sox', 'Sarbanes-Oxley (SOX)', false, NOW() - INTERVAL '120 days'),
('demo-financeglobal', 'pci-dss', 'PCI-DSS v4.0', false, NOW() - INTERVAL '110 days'),

-- HealthTech Frameworks (2)
('demo-healthtech', 'hipaa', 'HIPAA Security Rule', false, NOW() - INTERVAL '100 days'),
('demo-healthtech', 'hitrust', 'HITRUST CSF v11', false, NOW() - INTERVAL '90 days'),

-- DevShop Frameworks (2)
('demo-devshop', 'nist-csf', 'NIST Cybersecurity Framework', false, NOW() - INTERVAL '45 days'),
('demo-devshop', 'custom-devops-security', 'DevShop Security Standards', true, NOW() - INTERVAL '40 days')
ON CONFLICT DO NOTHING;

-- Summary: 10 compliance frameworks (2 per tenant)
-- Standard frameworks: 8 (SOC2, ISO27001, SOX, PCI-DSS, HIPAA, HITRUST, NIST)
-- Custom frameworks: 2 (TechStart, DevShop)
-- HealthTech focuses on healthcare compliance (HIPAA, HITRUST)
-- FinanceGlobal focuses on financial compliance (SOX, PCI-DSS)

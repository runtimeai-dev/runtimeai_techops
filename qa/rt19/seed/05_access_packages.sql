-- Seed File: 05_access_packages.sql (SCHEMA-ALIGNED)
-- Purpose: Create 25 access packages (5 per tenant) for MSFT-40
-- Schema: id (UUID), tenant_id, name, description, permissions (JSONB array), tool_access (JSONB array), 
--         api_roles (JSONB array), collection_id (UUID), approval_stages (JSONB array), 
--         default_duration_days, max_duration_days, auto_renew, status, created_by, created_at

INSERT INTO access_packages (tenant_id, name, description, permissions, tool_access, api_roles, approval_stages, default_duration_days, max_duration_days, auto_renew, status, created_by, created_at) VALUES
-- ACME Corp Packages (5)
('demo-acme-corp', 'Developer Standard Access', 'Standard access for developers', 
 '["read_agents", "write_agents", "read_tools"]'::jsonb, 
 '["tool-acme-github", "tool-acme-slack", "tool-acme-datadog"]'::jsonb,
 '["developer"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-acme-corp.local", "required": true}]'::jsonb,
 90, 365, false, 'published', 'admin@demo-acme-corp.local', NOW() - INTERVAL '90 days'),

('demo-acme-corp', 'Production Agent Access', 'Access to production agents and tools',
 '["read_agents", "execute_agents", "read_tools"]'::jsonb,
 '["tool-acme-postgres", "tool-acme-salesforce", "tool-acme-stripe"]'::jsonb,
 '["operator"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-acme-corp.local", "required": true}, {"stage": 2, "approver": "auditor@demo-acme-corp.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-acme-corp.local', NOW() - INTERVAL '80 days'),

('demo-acme-corp', 'Analytics Access', 'Read-only access to analytics tools',
 '["read_agents", "read_tools", "read_metrics"]'::jsonb,
 '["tool-acme-analytics", "tool-acme-datadog"]'::jsonb,
 '["analyst"]'::jsonb,
 '[]'::jsonb,
 180, 365, true, 'published', 'admin@demo-acme-corp.local', NOW() - INTERVAL '70 days'),

('demo-acme-corp', 'Admin Full Access', 'Full administrative access',
 '["*"]'::jsonb,
 '["*"]'::jsonb,
 '["admin"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-acme-corp.local", "required": true}]'::jsonb,
 365, 365, false, 'published', 'admin@demo-acme-corp.local', NOW() - INTERVAL '60 days'),

('demo-acme-corp', 'Temporary Contractor Access', 'Limited access for contractors',
 '["read_agents", "read_tools"]'::jsonb,
 '["tool-acme-slack"]'::jsonb,
 '["contractor"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-acme-corp.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-acme-corp.local', NOW() - INTERVAL '50 days'),

-- TechStart Packages (5)
('demo-techstart', 'Developer Access', 'Full development environment access',
 '["read_agents", "write_agents", "execute_agents", "read_tools", "write_tools"]'::jsonb,
 '["tool-tech-github", "tool-tech-vercel", "tool-tech-postgres", "tool-tech-redis"]'::jsonb,
 '["developer", "operator"]'::jsonb,
 '[]'::jsonb,
 90, 365, true, 'published', 'admin@demo-techstart.local', NOW() - INTERVAL '60 days'),

('demo-techstart', 'Staging Environment Access', 'Access to staging agents',
 '["read_agents", "execute_agents"]'::jsonb,
 '["tool-tech-vercel", "tool-tech-redis"]'::jsonb,
 '["operator"]'::jsonb,
 '[]'::jsonb,
 90, 180, false, 'published', 'admin@demo-techstart.local', NOW() - INTERVAL '55 days'),

('demo-techstart', 'Monitoring Access', 'Read-only monitoring access',
 '["read_metrics", "read_logs"]'::jsonb,
 '["tool-tech-prometheus", "tool-tech-slack"]'::jsonb,
 '["viewer"]'::jsonb,
 '[]'::jsonb,
 180, 365, true, 'published', 'admin@demo-techstart.local', NOW() - INTERVAL '50 days'),

('demo-techstart', 'Production Deploy Access', 'Production deployment permissions',
 '["execute_agents", "write_agents"]'::jsonb,
 '["tool-tech-vercel", "tool-tech-docker"]'::jsonb,
 '["operator"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-techstart.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-techstart.local', NOW() - INTERVAL '45 days'),

('demo-techstart', 'Intern Access', 'Limited access for interns',
 '["read_agents", "read_tools"]'::jsonb,
 '["tool-tech-slack", "tool-tech-notion"]'::jsonb,
 '["intern"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-techstart.local", "required": true}]'::jsonb,
 30, 90, false, 'draft', 'admin@demo-techstart.local', NOW() - INTERVAL '40 days'),

-- FinanceGlobal Packages (5)
('demo-financeglobal', 'SOX Compliant Access', 'SOX-compliant agent access',
 '["read_agents", "execute_agents"]'::jsonb,
 '["tool-fin-postgres", "tool-fin-tableau"]'::jsonb,
 '["analyst"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-financeglobal.local", "required": true}, {"stage": 2, "approver": "auditor@demo-financeglobal.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-financeglobal.local', NOW() - INTERVAL '120 days'),

('demo-financeglobal', 'Auditor Access', 'Read-only access for auditors',
 '["read_agents", "read_tools", "read_logs", "read_audit"]'::jsonb,
 '["tool-fin-tableau", "tool-fin-powerbi"]'::jsonb,
 '["auditor"]'::jsonb,
 '[]'::jsonb,
 365, 365, true, 'published', 'admin@demo-financeglobal.local', NOW() - INTERVAL '110 days'),

('demo-financeglobal', 'Trading Bot Access', 'Access to trading algorithms',
 '["execute_agents"]'::jsonb,
 '["tool-fin-postgres", "tool-fin-stripe"]'::jsonb,
 '["trader"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-financeglobal.local", "required": true}, {"stage": 2, "approver": "compliance@demo-financeglobal.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-financeglobal.local', NOW() - INTERVAL '100 days'),

('demo-financeglobal', 'Risk Analysis Access', 'Access to risk analysis tools',
 '["read_agents", "execute_agents", "read_tools"]'::jsonb,
 '["tool-fin-tableau", "tool-fin-powerbi", "tool-fin-datadog"]'::jsonb,
 '["risk_analyst"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-financeglobal.local", "required": true}]'::jsonb,
 90, 180, false, 'published', 'admin@demo-financeglobal.local', NOW() - INTERVAL '90 days'),

('demo-financeglobal', 'Compliance Officer Access', 'Full compliance access',
 '["read_agents", "read_tools", "read_logs", "read_audit", "write_policies"]'::jsonb,
 '["*"]'::jsonb,
 '["compliance_officer"]'::jsonb,
 '[]'::jsonb,
 365, 365, true, 'published', 'admin@demo-financeglobal.local', NOW() - INTERVAL '80 days'),

-- HealthTech Packages (5)
('demo-healthtech', 'HIPAA PHI Access', 'HIPAA-compliant PHI access',
 '["read_agents", "execute_agents", "access_phi"]'::jsonb,
 '["tool-health-epic", "tool-health-cerner", "tool-health-postgres"]'::jsonb,
 '["clinician"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-healthtech.local", "required": true}, {"stage": 2, "approver": "privacy-officer@demo-healthtech.local", "required": true}]'::jsonb,
 30, 90, false, 'published', 'admin@demo-healthtech.local', NOW() - INTERVAL '100 days'),

('demo-healthtech', 'Privacy Officer Access', 'Privacy and compliance access',
 '["read_agents", "read_tools", "read_logs", "read_audit", "access_phi"]'::jsonb,
 '["*"]'::jsonb,
 '["privacy_officer"]'::jsonb,
 '[]'::jsonb,
 365, 365, true, 'published', 'admin@demo-healthtech.local', NOW() - INTERVAL '90 days'),

('demo-healthtech', 'Research Access', 'De-identified data access for research',
 '["read_agents", "execute_agents"]'::jsonb,
 '["tool-health-postgres", "tool-health-datadog"]'::jsonb,
 '["researcher"]'::jsonb,
 '[{"stage": 1, "approver": "privacy-officer@demo-healthtech.local", "required": true}]'::jsonb,
 90, 180, false, 'published', 'admin@demo-healthtech.local', NOW() - INTERVAL '80 days'),

('demo-healthtech', 'IT Support Access', 'Technical support access',
 '["read_agents", "read_tools", "read_logs"]'::jsonb,
 '["tool-health-datadog", "tool-health-slack"]'::jsonb,
 '["support"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-healthtech.local", "required": true}]'::jsonb,
 90, 180, false, 'published', 'admin@demo-healthtech.local', NOW() - INTERVAL '70 days'),

('demo-healthtech', 'Emergency Access', 'Break-glass emergency access',
 '["*"]'::jsonb,
 '["*"]'::jsonb,
 '["emergency"]'::jsonb,
 '[]'::jsonb,
 1, 7, false, 'published', 'admin@demo-healthtech.local', NOW() - INTERVAL '60 days'),

-- DevShop Packages (5)
('demo-devshop', 'Full Dev Access', 'Complete development access',
 '["*"]'::jsonb,
 '["*"]'::jsonb,
 '["developer", "operator"]'::jsonb,
 '[]'::jsonb,
 180, 365, true, 'published', 'admin@demo-devshop.local', NOW() - INTERVAL '45 days'),

('demo-devshop', 'CI/CD Access', 'Automated deployment access',
 '["execute_agents", "write_agents"]'::jsonb,
 '["tool-dev-github", "tool-dev-docker", "tool-dev-vercel"]'::jsonb,
 '["ci_cd"]'::jsonb,
 '[]'::jsonb,
 365, 365, true, 'published', 'admin@demo-devshop.local', NOW() - INTERVAL '40 days'),

('demo-devshop', 'QA Tester Access', 'Testing environment access',
 '["read_agents", "execute_agents", "read_tools"]'::jsonb,
 '["tool-dev-postgres", "tool-dev-redis"]'::jsonb,
 '["qa"]'::jsonb,
 '[]'::jsonb,
 90, 180, false, 'published', 'admin@demo-devshop.local', NOW() - INTERVAL '35 days'),

('demo-devshop', 'Monitoring Access', 'Metrics and logs access',
 '["read_metrics", "read_logs"]'::jsonb,
 '["tool-dev-prometheus", "tool-dev-grafana"]'::jsonb,
 '["viewer"]'::jsonb,
 '[]'::jsonb,
 180, 365, true, 'published', 'admin@demo-devshop.local', NOW() - INTERVAL '30 days'),

('demo-devshop', 'Contractor Access', 'Limited contractor access',
 '["read_agents", "read_tools"]'::jsonb,
 '["tool-dev-slack", "tool-dev-github"]'::jsonb,
 '["contractor"]'::jsonb,
 '[{"stage": 1, "approver": "admin@demo-devshop.local", "required": true}]'::jsonb,
 30, 90, false, 'draft', 'admin@demo-devshop.local', NOW() - INTERVAL '25 days')
ON CONFLICT DO NOTHING;

-- Summary: 25 access packages (5 per tenant)
-- Status: 22 published, 3 draft
-- Approval stages: 12 with approvals, 13 without

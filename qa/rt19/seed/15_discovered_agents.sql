-- Seed File: 15_discovered_agents.sql (SCHEMA-ALIGNED)
-- Purpose: Create 15 discovered agents (Shadow AI) across 5 tenants
-- Schema: id (UUID), tenant_id, fingerprint, name, owner, source_details (JSONB), last_seen, status, capabilities (JSONB), lifecycle_status, verification_status, endpoint

INSERT INTO discovered_agents (tenant_id, fingerprint, name, owner, source_details, last_seen, status, capabilities, lifecycle_status, verification_status, endpoint) VALUES
-- ACME Corp Discovered Agents (3 entries - Shadow AI)
('demo-acme-corp', 'fp-acme-shadow-001', 'UnknownDataBot', 'unknown@demo-acme-corp.local', '{"discovery_method": "network_scan", "ip_address": "10.0.1.45", "port": 8080, "user_agent": "Python/3.11 aiohttp/3.8.0", "first_seen": "2026-02-10T14:30:00Z"}', NOW() - INTERVAL '2 hours', 'unmanaged', '["api_calls", "data_collection", "external_communication"]', 'active', 'unverified', 'http://10.0.1.45:8080'),
('demo-acme-corp', 'fp-acme-shadow-002', 'RogueAutomationScript', 'developer@demo-acme-corp.local', '{"discovery_method": "log_analysis", "script_path": "/home/dev/scripts/auto_export.py", "cron_schedule": "0 */6 * * *", "first_seen": "2026-02-08T09:00:00Z"}', NOW() - INTERVAL '6 hours', 'unmanaged', '["database_access", "file_export", "email_sending"]', 'active', 'unverified', NULL),
('demo-acme-corp', 'fp-acme-shadow-003', 'LegacyIntegrationBot', 'legacy-system@demo-acme-corp.local', '{"discovery_method": "api_gateway_logs", "api_key_prefix": "sk-legacy-", "request_pattern": "POST /v1/agents", "first_seen": "2026-01-15T00:00:00Z"}', NOW() - INTERVAL '1 day', 'unmanaged', '["api_integration", "legacy_system_access"]', 'warning', 'unverified', 'https://legacy.acme-corp.internal/api'),

-- TechStart Discovered Agents (3 entries - Shadow AI)
('demo-techstart', 'fp-tech-shadow-001', 'SlackBotUnauthorized', 'engineer@demo-techstart.local', '{"discovery_method": "slack_audit_log", "bot_user_id": "B01234ABCD", "workspace_id": "T56789EFGH", "scopes": ["chat:write", "files:read", "channels:history"], "first_seen": "2026-02-12T10:30:00Z"}', NOW() - INTERVAL '4 hours', 'unmanaged', '["slack_posting", "file_access", "message_reading"]', 'active', 'unverified', 'https://slack.com/api'),
('demo-techstart', 'fp-tech-shadow-002', 'LocalDevAgent', 'developer@demo-techstart.local', '{"discovery_method": "localhost_scan", "ip_address": "127.0.0.1", "port": 3000, "process_name": "node dev-agent.js", "first_seen": "2026-02-14T15:00:00Z"}', NOW() - INTERVAL '30 minutes', 'unmanaged', '["code_generation", "api_testing"]', 'active', 'unverified', 'http://localhost:3000'),
('demo-techstart', 'fp-tech-shadow-003', 'GitHubActionBot', 'ci-cd@demo-techstart.local', '{"discovery_method": "github_audit", "workflow_file": ".github/workflows/deploy.yml", "action_name": "auto-deploy-agent", "first_seen": "2026-02-01T00:00:00Z"}', NOW() - INTERVAL '12 hours', 'unmanaged', '["ci_cd", "deployment", "github_api"]', 'active', 'unverified', 'https://api.github.com'),

-- FinanceGlobal Discovered Agents (3 entries - Shadow AI)
('demo-financeglobal', 'fp-finance-shadow-001', 'UnauthorizedTradingBot', 'trader@demo-financeglobal.local', '{"discovery_method": "database_audit", "database": "trading_db", "connection_source": "10.1.5.78", "queries_per_minute": 150, "first_seen": "2026-02-09T08:00:00Z"}', NOW() - INTERVAL '1 hour', 'unmanaged', '["database_access", "trading", "market_data_access"]', 'suspended', 'unverified', NULL),
('demo-financeglobal', 'fp-finance-shadow-002', 'ExcelMacroBot', 'analyst@demo-financeglobal.local', '{"discovery_method": "file_access_log", "file_path": "C:\\\\Users\\\\analyst\\\\Documents\\\\auto_report.xlsm", "macro_name": "GenerateReport", "first_seen": "2026-01-20T00:00:00Z"}', NOW() - INTERVAL '8 hours', 'unmanaged', '["excel_automation", "report_generation", "email_sending"]', 'active', 'unverified', NULL),
('demo-financeglobal', 'fp-finance-shadow-003', 'ThirdPartyRiskBot', 'vendor@external.com', '{"discovery_method": "api_gateway_logs", "api_key_prefix": "sk-vendor-", "source_ip": "203.0.113.45", "request_pattern": "GET /api/risk-scores", "first_seen": "2026-02-05T00:00:00Z"}', NOW() - INTERVAL '3 hours', 'unmanaged', '{"api_access", "risk_analysis", "external_communication"]', 'warning', 'unverified', 'https://vendor-api.external.com'),

-- HealthTech Discovered Agents (3 entries - Shadow AI)
('demo-healthtech', 'fp-health-shadow-001', 'UnmanagedPHIBot', 'doctor@demo-healthtech.local', '{"discovery_method": "ehr_audit_log", "ehr_system": "Epic", "user_id": "DR12345", "phi_access_count": 250, "first_seen": "2026-02-07T11:00:00Z"}', NOW() - INTERVAL '2 hours', 'unmanaged', '["phi_access", "ehr_integration", "patient_data_read"]', 'suspended', 'unverified', 'https://epic.demo-healthtech.internal'),
('demo-healthtech', 'fp-health-shadow-002', 'ResearchDataBot', 'researcher@demo-healthtech.local', '{"discovery_method": "database_audit", "database": "research_db", "connection_source": "10.2.3.56", "queries_per_day": 500, "first_seen": "2026-01-25T00:00:00Z"}', NOW() - INTERVAL '5 hours', 'unmanaged', '["database_access", "data_analysis", "research"]', 'active', 'unverified', NULL),
('demo-healthtech', 'fp-health-shadow-003', 'OpenAIIntegration', 'developer@demo-healthtech.local', '{"discovery_method": "network_traffic_analysis", "destination": "api.openai.com", "api_key_prefix": "sk-proj-", "no_baa": true, "first_seen": "2026-02-11T09:30:00Z"}', NOW() - INTERVAL '1 hour', 'unmanaged', '["llm_api", "phi_processing", "external_communication"]', 'suspended', 'unverified', 'https://api.openai.com/v1'),

-- DevShop Discovered Agents (3 entries - Shadow AI)
('demo-devshop', 'fp-devops-shadow-001', 'LocalDockerAgent', 'devops@demo-devshop.local', '{"discovery_method": "docker_ps", "container_id": "abc123def456", "image": "custom-agent:latest", "ports": ["8080:8080"], "first_seen": "2026-02-13T14:00:00Z"}', NOW() - INTERVAL '30 minutes', 'unmanaged', '["docker_api", "container_management"]', 'active', 'unverified', 'http://localhost:8080'),
('demo-devshop', 'fp-devops-shadow-002', 'JenkinsPluginBot', 'jenkins@demo-devshop.local', '{"discovery_method": "jenkins_audit", "plugin_name": "auto-deploy-plugin", "version": "1.2.3", "job_name": "production-deploy", "first_seen": "2026-02-06T00:00:00Z"}', NOW() - INTERVAL '4 hours', 'unmanaged', '["ci_cd", "deployment", "jenkins_api"]', 'active', 'unverified', 'http://jenkins.demo-devshop.internal:8080'),
('demo-devshop', 'fp-devops-shadow-003', 'KubernetesOperator', 'k8s-system@demo-devshop.local', '{"discovery_method": "k8s_api_audit", "namespace": "default", "pod_name": "custom-operator-xyz", "service_account": "default", "first_seen": "2026-02-10T12:00:00Z"}', NOW() - INTERVAL '2 hours', 'unmanaged', '["kubernetes_api", "pod_management", "deployment"]', 'active', 'unverified', 'https://k8s.demo-devshop.internal:6443')
ON CONFLICT DO NOTHING;

-- Summary: 15 discovered agents (Shadow AI) (3 per tenant)
-- Discovery methods: network_scan, log_analysis, api_gateway_logs, slack_audit_log, localhost_scan, github_audit, database_audit, file_access_log, ehr_audit_log, network_traffic_analysis, docker_ps, jenkins_audit, k8s_api_audit
-- Status: all unmanaged (Shadow AI)
-- Lifecycle status: 10 active, 2 warning, 3 suspended
-- Verification status: all unverified
-- Capabilities: Various unauthorized capabilities including PHI access, trading, database access, external communication
-- Time range: last_seen from 1 day ago to 30 minutes ago

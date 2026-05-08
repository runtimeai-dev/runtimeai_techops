-- Seed File: 03_agents.sql (MINIMAL WORKING VERSION)
-- Purpose: Create 50 agents (10 per tenant) with proper schema
-- Schema: agent_id, tenant_id, name, status, owner, environment, skills (JSONB array)

INSERT INTO agents (agent_id, tenant_id, name, status, owner, environment, skills, created_at) VALUES
-- ACME Corp Agents (10)
('az-agent-acme-001', 'demo-acme-corp', 'CustomerSupportBot', 'active', 'admin@demo-acme-corp.local', 'prod', '["customer_service", "chat_support", "email_processing"]', NOW() - INTERVAL '90 days'),
('az-agent-acme-002', 'demo-acme-corp', 'DataAnalystBot', 'active', 'admin@demo-acme-corp.local', 'prod', '["data_analysis", "reporting", "data_mining"]', NOW() - INTERVAL '80 days'),
('az-agent-acme-003', 'demo-acme-corp', 'SalesAssistant', 'active', 'admin@demo-acme-corp.local', 'prod', '["sales_automation", "customer_service"]', NOW() - INTERVAL '70 days'),
('az-agent-acme-004', 'demo-acme-corp', 'SecurityScanner', 'active', 'admin@demo-acme-corp.local', 'prod', '["security_scanning", "alerting"]', NOW() - INTERVAL '60 days'),
('az-agent-acme-005', 'demo-acme-corp', 'BackupBot', 'active', 'admin@demo-acme-corp.local', 'staging', '["backup_management", "file_system_access"]', NOW() - INTERVAL '50 days'),
('az-agent-acme-006', 'demo-acme-corp', 'LogAggregator', 'active', 'admin@demo-acme-corp.local', 'staging', '["log_aggregation", "metrics_collection"]', NOW() - INTERVAL '40 days'),
('az-agent-acme-007', 'demo-acme-corp', 'DeploymentAgent', 'active', 'admin@demo-acme-corp.local', 'dev', '["deployment", "testing"]', NOW() - INTERVAL '30 days'),
('az-agent-acme-008', 'demo-acme-corp', 'TestRunner', 'active', 'admin@demo-acme-corp.local', 'dev', '["testing", "code_review"]', NOW() - INTERVAL '20 days'),
('az-agent-acme-009', 'demo-acme-corp', 'APIGateway', 'active', 'admin@demo-acme-corp.local', 'prod', '["api_gateway", "load_balancing"]', NOW() - INTERVAL '10 days'),
('az-agent-acme-010', 'demo-acme-corp', 'MetricsCollector', 'inactive', 'admin@demo-acme-corp.local', 'dev', '["metrics_collection", "alerting"]', NOW() - INTERVAL '5 days'),

-- TechStart Agents (10)
('az-agent-tech-001', 'demo-techstart', 'DevAssistant', 'active', 'admin@demo-techstart.local', 'dev', '["code_review", "documentation"]', NOW() - INTERVAL '60 days'),
('az-agent-tech-002', 'demo-techstart', 'CI_CD_Bot', 'active', 'admin@demo-techstart.local', 'staging', '["deployment", "testing"]', NOW() - INTERVAL '55 days'),
('az-agent-tech-003', 'demo-techstart', 'MonitoringBot', 'active', 'admin@demo-techstart.local', 'prod', '["metrics_collection", "alerting", "log_aggregation"]', NOW() - INTERVAL '50 days'),
('az-agent-tech-004', 'demo-techstart', 'ChatBot', 'active', 'admin@demo-techstart.local', 'prod', '["chat_support", "customer_service"]', NOW() - INTERVAL '45 days'),
('az-agent-tech-005', 'demo-techstart', 'DataPipeline', 'active', 'admin@demo-techstart.local', 'prod', '["data_analysis", "queue_processing"]', NOW() - INTERVAL '40 days'),
('az-agent-tech-006', 'demo-techstart', 'SecurityBot', 'active', 'admin@demo-techstart.local', 'staging', '["security_scanning"]', NOW() - INTERVAL '35 days'),
('az-agent-tech-007', 'demo-techstart', 'BackupAgent', 'active', 'admin@demo-techstart.local', 'dev', '["backup_management"]', NOW() - INTERVAL '30 days'),
('az-agent-tech-008', 'demo-techstart', 'LoadBalancer', 'active', 'admin@demo-techstart.local', 'prod', '["load_balancing", "api_gateway"]', NOW() - INTERVAL '25 days'),
('az-agent-tech-009', 'demo-techstart', 'CacheManager', 'active', 'admin@demo-techstart.local', 'staging', '["caching"]', NOW() - INTERVAL '20 days'),
('az-agent-tech-010', 'demo-techstart', 'QueueWorker', 'inactive', 'admin@demo-techstart.local', 'dev', '["queue_processing"]', NOW() - INTERVAL '15 days'),

-- FinanceGlobal Agents (10)
('az-agent-fin-001', 'demo-financeglobal', 'RiskAnalysisBot', 'active', 'admin@demo-financeglobal.local', 'prod', '["data_analysis", "reporting", "pii_access"]', NOW() - INTERVAL '120 days'),
('az-agent-fin-002', 'demo-financeglobal', 'FraudDetectionAI', 'active', 'admin@demo-financeglobal.local', 'prod', '["security_scanning", "alerting", "pii_access"]', NOW() - INTERVAL '110 days'),
('az-agent-fin-003', 'demo-financeglobal', 'TradingBot', 'active', 'admin@demo-financeglobal.local', 'prod', '["data_analysis", "database_access"]', NOW() - INTERVAL '100 days'),
('az-agent-fin-004', 'demo-financeglobal', 'ComplianceBot', 'active', 'admin@demo-financeglobal.local', 'prod', '["reporting", "documentation"]', NOW() - INTERVAL '90 days'),
('az-agent-fin-005', 'demo-financeglobal', 'AuditLogger', 'active', 'admin@demo-financeglobal.local', 'prod', '["log_aggregation", "reporting"]', NOW() - INTERVAL '80 days'),
('az-agent-fin-006', 'demo-financeglobal', 'DataWarehouse', 'active', 'admin@demo-financeglobal.local', 'prod', '["database_access", "data_analysis"]', NOW() - INTERVAL '70 days'),
('az-agent-fin-007', 'demo-financeglobal', 'ReportGenerator', 'active', 'admin@demo-financeglobal.local', 'staging', '["reporting", "documentation"]', NOW() - INTERVAL '60 days'),
('az-agent-fin-008', 'demo-financeglobal', 'BackupAgent', 'active', 'admin@demo-financeglobal.local', 'prod', '["backup_management", "database_access"]', NOW() - INTERVAL '50 days'),
('az-agent-fin-009', 'demo-financeglobal', 'SecurityMonitor', 'active', 'admin@demo-financeglobal.local', 'prod', '["security_scanning", "alerting"]', NOW() - INTERVAL '40 days'),
('az-agent-fin-010', 'demo-financeglobal', 'TestAgent', 'inactive', 'admin@demo-financeglobal.local', 'dev', '["testing"]', NOW() - INTERVAL '30 days'),

-- HealthTech Agents (10)
('az-agent-health-001', 'demo-healthtech', 'PHI_AnalysisBot', 'active', 'admin@demo-healthtech.local', 'prod', '["data_analysis", "pii_access"]', NOW() - INTERVAL '100 days'),
('az-agent-health-002', 'demo-healthtech', 'DiagnosisAssistant', 'active', 'admin@demo-healthtech.local', 'prod', '["data_analysis", "pii_access"]', NOW() - INTERVAL '90 days'),
('az-agent-health-003', 'demo-healthtech', 'PatientCareBot', 'active', 'admin@demo-healthtech.local', 'prod', '["customer_service", "chat_support", "pii_access"]', NOW() - INTERVAL '80 days'),
('az-agent-health-004', 'demo-healthtech', 'EHR_Integration', 'active', 'admin@demo-healthtech.local', 'prod', '["database_access", "pii_access"]', NOW() - INTERVAL '70 days'),
('az-agent-health-005', 'demo-healthtech', 'ComplianceMonitor', 'active', 'admin@demo-healthtech.local', 'prod', '["security_scanning", "reporting"]', NOW() - INTERVAL '60 days'),
('az-agent-health-006', 'demo-healthtech', 'AuditLogger', 'active', 'admin@demo-healthtech.local', 'prod', '["log_aggregation", "pii_access"]', NOW() - INTERVAL '50 days'),
('az-agent-health-007', 'demo-healthtech', 'BackupAgent', 'active', 'admin@demo-healthtech.local', 'staging', '["backup_management", "database_access"]', NOW() - INTERVAL '40 days'),
('az-agent-health-008', 'demo-healthtech', 'ReportGenerator', 'active', 'admin@demo-healthtech.local', 'staging', '["reporting", "pii_access"]', NOW() - INTERVAL '30 days'),
('az-agent-health-009', 'demo-healthtech', 'SecurityBot', 'active', 'admin@demo-healthtech.local', 'prod', '["security_scanning", "alerting"]', NOW() - INTERVAL '20 days'),
('az-agent-health-010', 'demo-healthtech', 'TestAgent', 'inactive', 'admin@demo-healthtech.local', 'dev', '["testing"]', NOW() - INTERVAL '10 days'),

-- DevShop Agents (10)
('az-agent-dev-001', 'demo-devshop', 'BuildBot', 'active', 'admin@demo-devshop.local', 'dev', '["deployment", "testing"]', NOW() - INTERVAL '45 days'),
('az-agent-dev-002', 'demo-devshop', 'TestRunner', 'active', 'admin@demo-devshop.local', 'dev', '["testing", "code_review"]', NOW() - INTERVAL '40 days'),
('az-agent-dev-003', 'demo-devshop', 'DeploymentAgent', 'active', 'admin@demo-devshop.local', 'staging', '["deployment"]', NOW() - INTERVAL '35 days'),
('az-agent-dev-004', 'demo-devshop', 'MonitoringBot', 'active', 'admin@demo-devshop.local', 'prod', '["metrics_collection", "alerting"]', NOW() - INTERVAL '30 days'),
('az-agent-dev-005', 'demo-devshop', 'LogCollector', 'active', 'admin@demo-devshop.local', 'prod', '["log_aggregation"]', NOW() - INTERVAL '25 days'),
('az-agent-dev-006', 'demo-devshop', 'SecurityScanner', 'active', 'admin@demo-devshop.local', 'staging', '["security_scanning"]', NOW() - INTERVAL '20 days'),
('az-agent-dev-007', 'demo-devshop', 'CodeReviewer', 'active', 'admin@demo-devshop.local', 'dev', '["code_review", "documentation"]', NOW() - INTERVAL '15 days'),
('az-agent-dev-008', 'demo-devshop', 'PerformanceTester', 'active', 'admin@demo-devshop.local', 'staging', '["testing", "metrics_collection"]', NOW() - INTERVAL '10 days'),
('az-agent-dev-009', 'demo-devshop', 'BackupAgent', 'active', 'admin@demo-devshop.local', 'dev', '["backup_management"]', NOW() - INTERVAL '5 days'),
('az-agent-dev-010', 'demo-devshop', 'ExperimentalBot', 'inactive', 'admin@demo-devshop.local', 'dev', '["testing"]', NOW() - INTERVAL '2 days')
ON CONFLICT (tenant_id, agent_id) DO NOTHING;

-- ── OPER_RT19-051a: Gap Closure Demo Agents ─────────────────
-- These agents are used by 18_flow_enforcer_gaps.sql and the
-- flow-enforcer gap closure QA / demo scripts.
INSERT INTO agents (agent_id, tenant_id, name, status, owner, environment, skills, created_at) VALUES
-- GAP-10: Blocked agent (is_blocked = true via /api/vendor-config/agent-check)
('az-agent-acme-blocked-001', 'demo-acme-corp', 'BlockedExfilBot',    'blocked',  'security@demo-acme-corp.local', 'prod',    '["data_exfiltration","bulk_export"]',          NOW() - INTERVAL '7 days'),
('az-agent-fs-blocked-001',   'felt-sense-ai',   'BlockedTradingBot',  'blocked',  'security@felt-sense-ai.ai',    'prod',    '["trading_execution","wire_transfer"]',         NOW() - INTERVAL '5 days'),

-- GAP-1 / GAP-2: High-drift agents triggering behavioral anomalies + DLP
('az-agent-acme-drift-001',   'demo-acme-corp', 'DriftAnalyticsBot',  'active',   'admin@demo-acme-corp.local',   'prod',    '["data_analysis","database_access","pii_access"]', NOW() - INTERVAL '14 days'),
('az-agent-fs-drift-001',     'felt-sense-ai',   'DriftReportingBot',  'active',   'admin@felt-sense-ai.ai',       'staging', '["reporting","database_access"]',               NOW() - INTERVAL '10 days'),

-- GAP-1: Sequence-anomaly agents (high velocity / tool enumeration)
('az-agent-acme-seq-001',     'demo-acme-corp', 'SeqTestBot',         'active',   'admin@demo-acme-corp.local',   'prod',    '["api_gateway","load_balancing","queue_processing"]', NOW() - INTERVAL '3 days'),
('az-agent-fs-seq-001',       'felt-sense-ai',   'SeqTradeBot',        'active',   'admin@felt-sense-ai.ai',       'prod',    '["trading_execution","data_analysis"]',         NOW() - INTERVAL '2 days')
ON CONFLICT (tenant_id, agent_id) DO NOTHING;

-- Summary: 50 base agents + 6 gap closure demo agents = 56 total
-- Status: 45 active, 5 inactive, 2 blocked (gap demo)
-- Environments: prod (25), staging (15), dev (10), plus 6 gap agents

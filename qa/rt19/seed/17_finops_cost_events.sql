-- FIN-001/FIN-090: AI FinOps Seed Data
-- Generates realistic cost events for 3 tenants, 20 agents, 5 providers

-- Agent cost events for Tenant A (bank-a)
INSERT INTO ai_cost_events (tenant_id, agent_id, provider, model, input_tokens, output_tokens, total_tokens, input_cost_usd, output_cost_usd, total_cost_usd, latency_ms, feature_tag, customer_id, team_id, created_at) VALUES
('tenant-a', 'agent-cx-1', 'openai', 'gpt-4o', 1420, 380, 1800, 0.00355000, 0.00380000, 0.00735000, 340, 'chat-support', 'customer-001', 'cx-team', NOW() - INTERVAL '1 hour'),
('tenant-a', 'agent-cx-1', 'openai', 'gpt-4o', 2100, 920, 3020, 0.00525000, 0.00920000, 0.01445000, 510, 'chat-support', 'customer-002', 'cx-team', NOW() - INTERVAL '2 hours'),
('tenant-a', 'agent-cx-1', 'anthropic', 'claude-3-haiku', 800, 200, 1000, 0.00020000, 0.00025000, 0.00045000, 120, 'chat-support', 'customer-001', 'cx-team', NOW() - INTERVAL '3 hours'),
('tenant-a', 'agent-fin-7', 'openai', 'gpt-4o', 5200, 2100, 7300, 0.01300000, 0.02100000, 0.03400000, 890, 'financial-analysis', 'customer-003', 'finance-team', NOW() - INTERVAL '1 hour'),
('tenant-a', 'agent-fin-7', 'openai', 'o1', 3400, 1800, 5200, 0.05100000, 0.10800000, 0.15900000, 2100, 'financial-analysis', 'customer-003', 'finance-team', NOW() - INTERVAL '4 hours'),
('tenant-a', 'agent-code-3', 'anthropic', 'claude-3.5-sonnet', 8200, 4100, 12300, 0.02460000, 0.06150000, 0.08610000, 1200, 'code-generation', 'customer-004', 'eng-team', NOW() - INTERVAL '2 hours'),
('tenant-a', 'agent-code-3', 'openai', 'gpt-4o-mini', 1200, 600, 1800, 0.00018000, 0.00036000, 0.00054000, 180, 'code-generation', 'customer-004', 'eng-team', NOW() - INTERVAL '5 hours'),
('tenant-a', 'agent-data-5', 'vertex', 'gemini-1.5-pro', 4500, 2200, 6700, 0.01575000, 0.02310000, 0.03885000, 750, 'data-analysis', 'customer-005', 'data-team', NOW() - INTERVAL '6 hours'),
('tenant-a', 'agent-data-5', 'vertex', 'gemini-1.5-flash', 3200, 1100, 4300, 0.00024000, 0.00033000, 0.00057000, 200, 'data-analysis', 'customer-005', 'data-team', NOW() - INTERVAL '8 hours'),
('tenant-a', 'agent-security-2', 'anthropic', 'claude-3-opus', 6800, 3200, 10000, 0.10200000, 0.24000000, 0.34200000, 3200, 'security-scan', 'customer-001', 'security-team', NOW() - INTERVAL '12 hours');

-- Agent cost events for Tenant B (fintech-b)
INSERT INTO ai_cost_events (tenant_id, agent_id, provider, model, input_tokens, output_tokens, total_tokens, input_cost_usd, output_cost_usd, total_cost_usd, latency_ms, feature_tag, customer_id, team_id, created_at) VALUES
('tenant-b', 'agent-trade-1', 'openai', 'o1', 4200, 2800, 7000, 0.06300000, 0.16800000, 0.23100000, 2800, 'trade-execution', 'client-alpha', 'trading-team', NOW() - INTERVAL '1 hour'),
('tenant-b', 'agent-trade-1', 'openai', 'gpt-4o', 2800, 1400, 4200, 0.00700000, 0.01400000, 0.02100000, 450, 'trade-execution', 'client-beta', 'trading-team', NOW() - INTERVAL '3 hours'),
('tenant-b', 'agent-risk-4', 'anthropic', 'claude-3.5-sonnet', 9200, 5100, 14300, 0.02760000, 0.07650000, 0.10410000, 1500, 'risk-assessment', 'client-alpha', 'risk-team', NOW() - INTERVAL '2 hours'),
('tenant-b', 'agent-kyc-2', 'bedrock', 'claude-3-sonnet', 3100, 1200, 4300, 0.00930000, 0.01800000, 0.02730000, 600, 'kyc-verification', 'client-gamma', 'compliance-team', NOW() - INTERVAL '5 hours'),
('tenant-b', 'agent-report-6', 'azure', 'gpt-4o', 5600, 3200, 8800, 0.01400000, 0.03200000, 0.04600000, 1100, 'report-gen', 'client-beta', 'analytics-team', NOW() - INTERVAL '7 hours');

-- Budget policies
INSERT INTO ai_cost_budgets (tenant_id, scope, scope_id, budget_usd, period, alert_threshold_pct, kill_switch) VALUES
('tenant-a', 'agent', 'agent-fin-7', 50.00, 'daily', 80, true),
('tenant-a', 'agent', 'agent-security-2', 100.00, 'daily', 80, true),
('tenant-a', 'team', 'cx-team', 500.00, 'monthly', 80, false),
('tenant-a', 'tenant', 'tenant-a', 5000.00, 'monthly', 80, true),
('tenant-b', 'agent', 'agent-trade-1', 200.00, 'daily', 90, true),
('tenant-b', 'tenant', 'tenant-b', 10000.00, 'monthly', 80, true);

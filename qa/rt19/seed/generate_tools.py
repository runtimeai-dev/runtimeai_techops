#!/usr/bin/env python3
"""
Generate 500 Tools across 5 demo tenants
Output: 04_tools.sql
"""

import random
import hashlib
from datetime import datetime, timedelta

TENANTS = [
    'demo-acme-corp',
    'demo-techstart',
    'demo-financeglobal',
    'demo-healthtech',
    'demo-devshop'
]

TOOLS_PER_TENANT = 100

# Tool categories and templates
TOOL_CATEGORIES = {
    'database': {
        'names': ['PostgreSQL Query', 'MySQL Admin', 'MongoDB Atlas', 'Redis Cache', 'DynamoDB Access'],
        'risk_tier': 'HIGH',
        'capabilities': ['execute_query', 'read_schema', 'write_data', 'admin_access']
    },
    'api': {
        'names': ['Salesforce CRM', 'HubSpot', 'Stripe Payment', 'Twilio SMS', 'SendGrid Email'],
        'risk_tier': 'MEDIUM',
        'capabilities': ['read_data', 'write_data', 'send_notification']
    },
    'messaging': {
        'names': ['Slack Notify', 'Teams Message', 'Discord Bot', 'Telegram Bot'],
        'risk_tier': 'LOW',
        'capabilities': ['send_message', 'read_channel']
    },
    'file_system': {
        'names': ['S3 Bucket', 'Google Drive', 'Dropbox', 'Azure Blob Storage'],
        'risk_tier': 'MEDIUM',
        'capabilities': ['read_file', 'write_file', 'delete_file']
    },
    'analytics': {
        'names': ['Google Analytics', 'Mixpanel', 'Amplitude', 'Segment'],
        'risk_tier': 'LOW',
        'capabilities': ['track_event', 'read_metrics']
    },
    'ai_services': {
        'names': ['OpenAI GPT-4', 'Anthropic Claude', 'Google Gemini', 'Cohere'],
        'risk_tier': 'MEDIUM',
        'capabilities': ['generate_text', 'analyze_content']
    },
    'payment': {
        'names': ['Stripe', 'PayPal', 'Square', 'Braintree'],
        'risk_tier': 'HIGH',
        'capabilities': ['process_payment', 'refund', 'read_transactions']
    },
    'auth': {
        'names': ['Auth0', 'Okta', 'Azure AD', 'Google OAuth'],
        'risk_tier': 'HIGH',
        'capabilities': ['authenticate', 'authorize', 'manage_users']
    },
    'monitoring': {
        'names': ['Datadog', 'New Relic', 'Prometheus', 'Grafana'],
        'risk_tier': 'LOW',
        'capabilities': ['read_metrics', 'create_alert']
    },
    'cicd': {
        'names': ['GitHub Actions', 'Jenkins', 'CircleCI', 'GitLab CI'],
        'risk_tier': 'MEDIUM',
        'capabilities': ['trigger_build', 'deploy', 'read_logs']
    }
}

def generate_tool_id():
    return 'tool-' + hashlib.md5(str(random.random()).encode()).hexdigest()[:16]

def generate_tool(tenant_id, index):
    """Generate a single tool"""
    # Select category
    category = random.choice(list(TOOL_CATEGORIES.keys()))
    template = TOOL_CATEGORIES[category]
    
    # Generate tool details
    tool_id = generate_tool_id()
    base_name = random.choice(template['names'])
    name = f"{base_name} - {index:03d}"
    uri = f"mcp://{base_name.lower().replace(' ', '-')}-{index}"
    
    # Risk tier with some randomness
    risk_tier = template['risk_tier']
    if random.random() < 0.2:  # 20% chance to vary
        risk_tier = random.choice(['HIGH', 'MEDIUM', 'LOW'])
    
    # Prod approval based on risk
    if risk_tier == 'HIGH':
        prod_ok = random.random() < 0.3  # 30% of HIGH approved
    elif risk_tier == 'MEDIUM':
        prod_ok = random.random() < 0.7  # 70% of MEDIUM approved
    else:
        prod_ok = random.random() < 0.95  # 95% of LOW approved
    
    # Quarantine status (5% of HIGH-risk tools)
    quarantined = risk_tier == 'HIGH' and random.random() < 0.05
    
    # Owner
    owners = ['admin', 'operator', 'alice', 'bob', 'dev1', 'dev2']
    owner = f"{random.choice(owners)}@{tenant_id}.local"
    
    # Created date (within last 6 months)
    days_ago = random.randint(1, 180)
    created_at = (datetime.now() - timedelta(days=days_ago)).isoformat()
    
    return {
        'tenant_id': tenant_id,
        'tool_id': tool_id,
        'uri': uri,
        'name': name,
        'owner': owner,
        'risk_tier': risk_tier,
        'prod_ok': prod_ok,
        'quarantined': quarantined,
        'created_at': created_at,
        'category': category
    }

# Generate SQL
print("-- Seed File: 04_tools.sql")
print("-- Purpose: Create 500 tools across 5 demo tenants")
print("-- Generated:", datetime.now().isoformat())
print()

tools = []

for tenant_id in TENANTS:
    for i in range(TOOLS_PER_TENANT):
        tool = generate_tool(tenant_id, i + 1)
        tools.append(tool)

# Output tools INSERT
print("-- Insert Tools")
print("INSERT INTO tools (tenant_id, tool_id, uri, owner, risk_tier, prod_ok, created_at) VALUES")
for i, tool in enumerate(tools):
    comma = ',' if i < len(tools) - 1 else ' ON CONFLICT (tenant_id, tool_id) DO NOTHING;'
    prod_ok_str = 'TRUE' if tool['prod_ok'] else 'FALSE'
    print(f"('{tool['tenant_id']}', '{tool['tool_id']}', '{tool['uri']}', '{tool['owner']}', '{tool['risk_tier']}', {prod_ok_str}, '{tool['created_at']}'){comma}")

print()
print("-- Summary Statistics")
print(f"-- Total tools: {len(tools)}")
print(f"-- HIGH risk: {sum(1 for t in tools if t['risk_tier'] == 'HIGH')}")
print(f"-- MEDIUM risk: {sum(1 for t in tools if t['risk_tier'] == 'MEDIUM')}")
print(f"-- LOW risk: {sum(1 for t in tools if t['risk_tier'] == 'LOW')}")
print(f"-- Prod approved: {sum(1 for t in tools if t['prod_ok'])}")
print(f"-- Quarantined: {sum(1 for t in tools if t['quarantined'])}")

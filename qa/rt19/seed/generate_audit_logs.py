#!/usr/bin/env python3
"""
Generate 5000 Audit Logs across 5 demo tenants
Output: 15_audit_logs.sql
"""

import random
from datetime import datetime, timedelta

TENANTS = [
    'demo-acme-corp',
    'demo-techstart',
    'demo-financeglobal',
    'demo-healthtech',
    'demo-devshop'
]

LOGS_PER_TENANT = 1000

# Action categories
ACTIONS = {
    'agent': ['agent.register', 'agent.update', 'agent.decommission', 'agent.certify'],
    'tool': ['tool.register', 'tool.quarantine', 'tool.release', 'tool.approve'],
    'access': ['access.request', 'access.approve', 'access.revoke', 'access.review'],
    'policy': ['policy.create', 'policy.update', 'policy.promote', 'policy.retire'],
    'user': ['user.login', 'user.logout', 'user.create', 'user.delete'],
    'drift': ['drift.detected', 'drift.resolved', 'drift.ignored'],
    'oauth': ['oauth.issue', 'oauth.revoke', 'oauth.rotate'],
    'workflow': ['workflow.execute', 'workflow.complete', 'workflow.fail'],
    'a2a': ['a2a.invoke', 'a2a.approve', 'a2a.deny'],
    'compliance': ['compliance.scan', 'compliance.gap_created', 'compliance.gap_resolved']
}

ACTORS = {
    'demo-acme-corp': ['admin@demo-acme-corp.local', 'alice@demo-acme-corp.local', 'bob@demo-acme-corp.local', 'operator@demo-acme-corp.local'],
    'demo-techstart': ['admin@demo-techstart.local', 'dev1@demo-techstart.local', 'dev2@demo-techstart.local'],
    'demo-financeglobal': ['admin@demo-financeglobal.local', 'ciso@demo-financeglobal.local', 'auditor@demo-financeglobal.local'],
    'demo-healthtech': ['admin@demo-healthtech.local', 'privacy-officer@demo-healthtech.local', 'operator@demo-healthtech.local'],
    'demo-devshop': ['admin@demo-devshop.local', 'lead@demo-devshop.local', 'dev@demo-devshop.local']
}

def generate_log(tenant_id, index):
    """Generate a single audit log"""
    # Select action
    category = random.choice(list(ACTIONS.keys()))
    action = random.choice(ACTIONS[category])
    
    # Select actor
    actor = random.choice(ACTORS[tenant_id])
    
    # Generate target based on action
    if 'agent' in action:
        target = f"az-agent-{random.randint(1, 250):03d}"
    elif 'tool' in action:
        target = f"tool-{random.randint(1, 500):03d}"
    elif 'user' in action:
        target = random.choice(ACTORS[tenant_id])
    elif 'policy' in action:
        target = f"v{random.randint(1, 3)}"
    elif 'access' in action:
        target = f"access-pkg-{random.randint(1, 100):03d}"
    elif 'workflow' in action:
        target = f"wf-{tenant_id.split('-')[1][:4]}-{random.randint(1, 3):03d}"
    elif 'oauth' in action:
        target = f"oauth-{tenant_id.split('-')[1][:4]}-{random.randint(1, 5):03d}"
    elif 'a2a' in action:
        target = f"a2a-{tenant_id.split('-')[1][:4]}-{random.randint(1, 5):03d}"
    elif 'compliance' in action:
        target = f"fw-{tenant_id.split('-')[1][:4]}-{random.choice(['soc2', 'pci', 'hipaa', 'iso'])}"
    else:
        target = f"resource-{index}"
    
    # Generate metadata based on action
    if action == 'user.login':
        metadata = f'{{"ip_address": "192.168.{random.randint(1, 255)}.{random.randint(1, 255)}", "user_agent": "Mozilla/5.0"}}'
    elif 'quarantine' in action:
        metadata = f'{{"reason": "Policy violation", "severity": "{random.choice(["high", "medium", "low"])}"}}'
    elif 'approve' in action:
        metadata = f'{{"approver": "{actor}", "justification": "Approved for production use"}}'
    elif 'drift' in action:
        metadata = f'{{"finding_type": "{random.choice(["unauthorized_capability", "policy_violation", "version_drift"])}", "severity": "{random.choice(["high", "medium", "low"])}"}}'
    else:
        metadata = '{}'
    
    # Generate timestamp (within last 30 days)
    days_ago = random.randint(0, 30)
    hours_ago = random.randint(0, 23)
    minutes_ago = random.randint(0, 59)
    created_at = datetime.now() - timedelta(days=days_ago, hours=hours_ago, minutes=minutes_ago)
    
    return {
        'tenant_id': tenant_id,
        'action': action,
        'actor': actor,
        'target': target,
        'metadata': metadata,
        'created_at': created_at.isoformat()
    }

# Generate SQL
print("-- Seed File: 15_audit_logs.sql")
print("-- Purpose: Create 5000 audit logs across 5 demo tenants")
print("-- Generated:", datetime.now().isoformat())
print()

logs = []

for tenant_id in TENANTS:
    for i in range(LOGS_PER_TENANT):
        log = generate_log(tenant_id, i + 1)
        logs.append(log)

# Sort by timestamp
logs.sort(key=lambda x: x['created_at'])

# Output audit logs INSERT
print("-- Insert Audit Logs")
print("INSERT INTO audit_logs (tenant_id, action, actor, target, metadata, created_at) VALUES")
for i, log in enumerate(logs):
    comma = ',' if i < len(logs) - 1 else ';'
    print(f"('{log['tenant_id']}', '{log['action']}', '{log['actor']}', '{log['target']}', '{log['metadata']}', '{log['created_at']}'){comma}")

print()
print("-- Summary Statistics")
print(f"-- Total audit logs: {len(logs)}")
print(f"-- Date range: {logs[0]['created_at']} to {logs[-1]['created_at']}")
print(f"-- Unique actions: {len(set(log['action'] for log in logs))}")
print(f"-- Unique actors: {len(set(log['actor'] for log in logs))}")

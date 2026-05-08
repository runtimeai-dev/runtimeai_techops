#!/usr/bin/env python3
"""
Generate Access Packages (MSFT-40) seed data
Output: 08_access_packages.sql
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

PACKAGE_TEMPLATES = [
    ('Customer Support Tools', 'Read-only access to customer data and support systems', True, 2),
    ('Database Admin Access', 'Full database administration capabilities', True, 3),
    ('Analytics Platform', 'Access to data analytics and BI tools', True, 2),
    ('API Gateway Access', 'Permission to deploy and manage API endpoints', True, 2),
    ('Security Scanner', 'Run security scans and view vulnerability reports', False, 1),
    ('Log Viewer', 'Read-only access to application logs', False, 1),
    ('Deployment Pipeline', 'Trigger deployments to staging and production', True, 3),
    ('Monitoring Dashboard', 'View system metrics and alerts', False, 1),
    ('File Storage Access', 'Read/write access to shared file storage', True, 2),
    ('Email Service', 'Send emails on behalf of the organization', True, 2),
    ('Slack Integration', 'Post messages to Slack channels', False, 1),
    ('Calendar Access', 'Read and create calendar events', True, 2),
    ('CRM Access', 'Access customer relationship management system', True, 2),
    ('Payment Processing', 'Process payments and refunds', True, 3),
    ('User Management', 'Create and manage user accounts', True, 3),
    ('Reporting Tools', 'Generate and export reports', False, 1),
    ('Backup System', 'Trigger and restore backups', True, 3),
    ('Network Config', 'Modify network and firewall rules', True, 3),
    ('Compliance Audit', 'Run compliance checks and audits', False, 2),
    ('Incident Response', 'Access incident management tools', True, 2),
]

def generate_package_id():
    return 'pkg-' + hashlib.md5(str(random.random()).encode()).hexdigest()[:16]

def generate_assignment_id():
    return 'assign-' + hashlib.md5(str(random.random()).encode()).hexdigest()[:16]

print("-- Seed File: 08_access_packages.sql")
print("-- Purpose: MSFT-40 Entitlement Management")
print("-- Generated:", datetime.now().isoformat())
print()

packages = []
assignments = []

# Generate 20 packages per tenant
for tenant_id in TENANTS:
    for i in range(20):
        template = random.choice(PACKAGE_TEMPLATES)
        pkg_id = generate_package_id()
        name = f"{template[0]} - {tenant_id.split('-')[-1].title()}"
        description = template[1]
        requires_approval = template[2]
        approval_stages = template[3] if requires_approval else 0
        
        # Random expiry (30-90 days)
        expiry_days = random.randint(30, 90)
        expiry_date = (datetime.now() + timedelta(days=expiry_days)).isoformat()
        
        packages.append({
            'id': pkg_id,
            'tenant_id': tenant_id,
            'name': name,
            'description': description,
            'requires_approval': requires_approval,
            'approval_stages': approval_stages,
            'max_duration_days': expiry_days,
            'created_at': datetime.now().isoformat()
        })
        
        # Create 2-5 assignments per package
        num_assignments = random.randint(2, 5)
        for j in range(num_assignments):
            assign_id = generate_assignment_id()
            # Assign to random agent (we'll use agent index)
            agent_index = random.randint(1, 50)
            agent_id = f"az-agent-{hashlib.md5(f'{tenant_id}-{agent_index}'.encode()).hexdigest()[:16]}"
            
            status = random.choices(['active', 'pending', 'expired'], weights=[70, 20, 10])[0]
            
            assignments.append({
                'id': assign_id,
                'tenant_id': tenant_id,
                'package_id': pkg_id,
                'agent_id': agent_id,
                'status': status,
                'assigned_at': datetime.now().isoformat(),
                'expires_at': expiry_date
            })

# Output SQL
print("-- Insert Access Packages")
print("INSERT INTO access_packages (id, tenant_id, name, description, requires_approval, approval_stages, max_duration_days, created_at) VALUES")
for i, pkg in enumerate(packages):
    comma = ',' if i < len(packages) - 1 else ';'
    print(f"('{pkg['id']}', '{pkg['tenant_id']}', '{pkg['name']}', '{pkg['description']}', {pkg['requires_approval']}, {pkg['approval_stages']}, {pkg['max_duration_days']}, '{pkg['created_at']}'){comma}")

print()
print("-- Insert Access Assignments")
print("INSERT INTO access_assignments (id, tenant_id, package_id, agent_id, status, assigned_at, expires_at) VALUES")
for i, assign in enumerate(assignments):
    comma = ',' if i < len(assignments) - 1 else ' ON CONFLICT (id) DO NOTHING;'
    print(f"('{assign['id']}', '{assign['tenant_id']}', '{assign['package_id']}', '{assign['agent_id']}', '{assign['status']}', '{assign['assigned_at']}', '{assign['expires_at']}'){comma}")

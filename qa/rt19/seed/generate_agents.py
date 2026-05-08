#!/usr/bin/env python3
"""
Generate 250 realistic agents across 5 demo tenants
Output: 03_agents.sql
"""

import random
import hashlib
from datetime import datetime, timedelta

# Configuration
TENANTS = [
    'demo-acme-corp',
    'demo-techstart',
    'demo-financeglobal',
    'demo-healthtech',
    'demo-devshop'
]

AGENTS_PER_TENANT = 50

# Agent name templates
AGENT_PREFIXES = [
    'DataAnalyst', 'CustomerSupport', 'SalesAssistant', 'CodeReviewer',
    'SecurityScanner', 'LogAggregator', 'MetricsCollector', 'AlertManager',
    'BackupBot', 'DeploymentAgent', 'TestRunner', 'DocGenerator',
    'EmailProcessor', 'ChatBot', 'ReportBuilder', 'DataMiner',
    'APIGateway', 'LoadBalancer', 'CacheManager', 'QueueWorker'
]

ENVIRONMENTS = ['dev', 'staging', 'prod']
STATUSES = ['active', 'inactive', 'deprecated']

# Skills/Capabilities
SKILLS = [
    'data_analysis', 'customer_service', 'sales_automation', 'code_review',
    'security_scanning', 'log_aggregation', 'metrics_collection', 'alerting',
    'backup_management', 'deployment', 'testing', 'documentation',
    'email_processing', 'chat_support', 'reporting', 'data_mining',
    'api_gateway', 'load_balancing', 'caching', 'queue_processing',
    'database_access', 'file_system_access', 'network_access', 'pii_access'
]

def generate_agent_id():
    """Generate unique agent ID"""
    return 'az-agent-' + hashlib.md5(str(random.random()).encode()).hexdigest()[:16]

def generate_agent(tenant_id, index):
    """Generate a single agent"""
    agent_id = generate_agent_id()
    prefix = random.choice(AGENT_PREFIXES)
    name = f"{prefix}-{index:03d}"
    status = random.choices(STATUSES, weights=[80, 15, 5])[0]  # 80% active
    environment = random.choice(ENVIRONMENTS)
    owner = f"admin@{tenant_id}.local"
    
    # Select 2-5 random skills
    num_skills = random.randint(2, 5)
    agent_skills = random.sample(SKILLS, num_skills)
    skills_json = '{' + ', '.join([f'"{s}"' for s in agent_skills]) + '}'
    
    # Created date (within last 6 months)
    days_ago = random.randint(1, 180)
    created_at = (datetime.now() - timedelta(days=days_ago)).isoformat()
    
    return {
        'agent_id': agent_id,
        'tenant_id': tenant_id,
        'name': name,
        'status': status,
        'owner': owner,
        'environment': environment,
        'skills': skills_json,
        'created_at': created_at
    }

def generate_sponsor(tenant_id, agent_id, owner):
    """Generate agent sponsor relationship"""
    return {
        'tenant_id': tenant_id,
        'agent_id': agent_id,
        'user_id': owner,
        'role': 'sponsor',
        'is_primary': 'TRUE',
        'assigned_at': datetime.now().isoformat()
    }

# Generate SQL
print("-- Seed File: 03_agents.sql")
print("-- Purpose: Create 250 agents across 5 demo tenants")
print("-- Generated:", datetime.now().isoformat())
print()

# Generate agents
agents = []
sponsors = []

for tenant_id in TENANTS:
    for i in range(AGENTS_PER_TENANT):
        agent = generate_agent(tenant_id, i + 1)
        agents.append(agent)
        sponsors.append(generate_sponsor(tenant_id, agent['agent_id'], agent['owner']))

# Output agents INSERT
print("-- Insert Agents")
print("INSERT INTO agents (agent_id, tenant_id, name, status, owner, environment, skills, created_at) VALUES")
for i, agent in enumerate(agents):
    comma = ',' if i < len(agents) - 1 else ';'
    print(f"('{agent['agent_id']}', '{agent['tenant_id']}', '{agent['name']}', '{agent['status']}', '{agent['owner']}', '{agent['environment']}', '{agent['skills']}', '{agent['created_at']}'){comma}")

print()
print("-- Insert Agent Sponsors")
print("INSERT INTO agent_sponsors (tenant_id, agent_id, user_id, role, is_primary, assigned_at) VALUES")
for i, sponsor in enumerate(sponsors):
    comma = ',' if i < len(sponsors) - 1 else ';'
    print(f"('{sponsor['tenant_id']}', '{sponsor['agent_id']}', '{sponsor['user_id']}', '{sponsor['role']}', {sponsor['is_primary']}, '{sponsor['assigned_at']}'){comma}")

print()
print("-- Create 5 Agent Collections (1 per tenant)")
collections = [
    ('demo-acme-corp', 'Production Agents', 'All production-grade agents'),
    ('demo-techstart', 'Development Bots', 'Experimental agents'),
    ('demo-financeglobal', 'Compliance Agents', 'SOC2-compliant agents'),
    ('demo-healthtech', 'HIPAA Agents', 'Healthcare-approved agents'),
    ('demo-devshop', 'Test Agents', 'QA and testing agents')
]

print("INSERT INTO agent_collections (id, tenant_id, name, description, created_at) VALUES")
for i, (tenant_id, name, desc) in enumerate(collections):
    comma = ',' if i < len(collections) - 1 else ';'
    collection_id = hashlib.md5(f"{tenant_id}-{name}".encode()).hexdigest()[:16]
    print(f"('{collection_id}', '{tenant_id}', '{name}', '{desc}', NOW()){comma}")

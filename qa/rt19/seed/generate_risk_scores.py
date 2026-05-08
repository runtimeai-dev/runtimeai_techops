#!/usr/bin/env python3
"""
Generate Agent Risk Scores (MSFT-42) seed data
Output: 10_risk_scores.sql
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

RISK_FACTORS = [
    'database_access',
    'pii_access',
    'file_system_write',
    'network_admin',
    'payment_processing',
    'external_api_access',
    'elevated_privileges',
    'no_mfa',
    'deprecated_version',
    'unencrypted_storage',
    'excessive_permissions',
    'anomalous_behavior'
]

DETECTION_TYPES = [
    'unusual_access_pattern',
    'privilege_escalation_attempt',
    'data_exfiltration_risk',
    'unauthorized_api_call',
    'suspicious_network_activity',
    'policy_violation',
    'credential_exposure',
    'malware_signature'
]

def calculate_risk_score(factors):
    """Calculate risk score based on factors"""
    base_score = len(factors) * 15
    if 'database_access' in factors:
        base_score += 20
    if 'pii_access' in factors:
        base_score += 25
    if 'payment_processing' in factors:
        base_score += 30
    return min(base_score, 100)

def generate_agent_id(tenant_id, index):
    return 'az-agent-' + hashlib.md5(f'{tenant_id}-{index}'.encode()).hexdigest()[:16]

print("-- Seed File: 10_risk_scores.sql")
print("-- Purpose: MSFT-42 Agent Risk Scoring")
print("-- Generated:", datetime.now().isoformat())
print()

risk_scores = []
detections = []

# Generate risk scores for all 250 agents
for tenant_id in TENANTS:
    for i in range(1, 51):  # 50 agents per tenant
        agent_id = generate_agent_id(tenant_id, i)
        
        # Select 1-4 random risk factors
        num_factors = random.randint(1, 4)
        factors = random.sample(RISK_FACTORS, num_factors)
        risk_score = calculate_risk_score(factors)
        
        # Determine risk level
        if risk_score >= 75:
            risk_level = 'critical'
        elif risk_score >= 50:
            risk_level = 'high'
        elif risk_score >= 25:
            risk_level = 'medium'
        else:
            risk_level = 'low'
        
        # Last calculated (within last 7 days)
        days_ago = random.randint(0, 7)
        last_calculated = (datetime.now() - timedelta(days=days_ago)).isoformat()
        
        risk_scores.append({
            'tenant_id': tenant_id,
            'agent_id': agent_id,
            'risk_score': risk_score,
            'risk_level': risk_level,
            'risk_factors': '{' + ', '.join([f'"{f}"' for f in factors]) + '}',
            'last_calculated_at': last_calculated
        })
        
        # Generate 0-3 detections for high/critical risk agents
        if risk_level in ['high', 'critical']:
            num_detections = random.randint(0, 3)
            for j in range(num_detections):
                detection_type = random.choice(DETECTION_TYPES)
                severity = random.choice(['low', 'medium', 'high'])
                detected_days_ago = random.randint(1, 30)
                detected_at = (datetime.now() - timedelta(days=detected_days_ago)).isoformat()
                
                detections.append({
                    'id': hashlib.md5(f'{agent_id}-{j}'.encode()).hexdigest()[:16],
                    'tenant_id': tenant_id,
                    'agent_id': agent_id,
                    'detection_type': detection_type,
                    'severity': severity,
                    'description': f'{detection_type.replace("_", " ").title()} detected',
                    'detected_at': detected_at
                })

# Output SQL
print("-- Insert Agent Risk Scores")
print("INSERT INTO agent_risk_scores (tenant_id, agent_id, risk_score, risk_level, risk_factors, last_calculated_at) VALUES")
for i, score in enumerate(risk_scores):
    comma = ',' if i < len(risk_scores) - 1 else ' ON CONFLICT (tenant_id, agent_id) DO UPDATE SET risk_score = EXCLUDED.risk_score, risk_level = EXCLUDED.risk_level, risk_factors = EXCLUDED.risk_factors, last_calculated_at = EXCLUDED.last_calculated_at;'
    print(f"('{score['tenant_id']}', '{score['agent_id']}', {score['risk_score']}, '{score['risk_level']}', '{score['risk_factors']}', '{score['last_calculated_at']}'){comma}")

if detections:
    print()
    print("-- Insert Agent Risk Detections")
    print("INSERT INTO agent_risk_detections (id, tenant_id, agent_id, detection_type, severity, description, detected_at) VALUES")
    for i, det in enumerate(detections):
        comma = ',' if i < len(detections) - 1 else ' ON CONFLICT (id) DO NOTHING;'
        print(f"('{det['id']}', '{det['tenant_id']}', '{det['agent_id']}', '{det['detection_type']}', '{det['severity']}', '{det['description']}', '{det['detected_at']}'){comma}")

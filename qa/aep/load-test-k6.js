import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const successCount = new Counter('success');

export const options = {
  vus: 100,  // 100 virtual agents
  duration: '5m',
  stages: [
    { duration: '1m', target: 50 },   // Ramp up to 50 agents
    { duration: '2m', target: 100 },  // Ramp up to 100 agents
    { duration: '1m', target: 50 },   // Ramp down to 50 agents
    { duration: '1m', target: 10 }    // Cool down
  ],
  thresholds: {
    'http_req_duration': ['p(99)<500'], // p99 latency must be <500ms
    'errors': ['rate<0.001'],             // Error rate <0.1%
    'response_time': ['p(95)<400']       // p95 latency <400ms
  }
};

const API_URL = __ENV.API_URL || 'https://aep-api.rt19.runtimeai.io';
const TOKEN = __ENV.TOKEN || 'test-token';

export default function () {
  // Test 1: List agents
  const listRes = http.get(`${API_URL}/api/cost-control/agents`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  check(listRes, { 'list agents 200': (r) => r.status === 200 }) || errorRate.add(1);
  responseTime.add(listRes.timings.duration);
  sleep(0.5);

  // Test 2: Audit logs
  const auditRes = http.get(`${API_URL}/api/audit-black-box/logs`, {
    headers: { 'Authorization': `Bearer ${TOKEN}` }
  });
  check(auditRes, { 'audit logs 200': (r) => r.status === 200 }) || errorRate.add(1);
  responseTime.add(auditRes.timings.duration);
  sleep(0.5);

  // Test 3: PII tokenization
  const piiRes = http.post(`${API_URL}/api/pii-shield/tokenize`,
    JSON.stringify({ data: 'user@example.com' }),
    { headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } }
  );
  check(piiRes, { 'PII tokenize 200': (r) => r.status === 200 }) || errorRate.add(1);
  responseTime.add(piiRes.timings.duration);
  sleep(0.5);
}

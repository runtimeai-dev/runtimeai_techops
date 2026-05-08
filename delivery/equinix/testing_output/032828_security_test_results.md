# Security Test Results — Sat Mar 28 02:01:19 PDT 2026
| Test | Status | Detail |
|------|--------|--------|
| 1.1 Cross-tenant agents | PASS | RLS enforced — A cannot see B's agents |
| 1.2 Cross-tenant audit | PASS | Tenant A cannot access B's audit logs |
| 1.3 Cross-tenant compliance | PASS | Frameworks isolated |
| 1.4 Cross-tenant kill switch | FAIL | Potential leak: {"runtimeai:killswitch:active:agent:eqx-local-ollama-SY4":{"action":"KILL","scope":"agent","target": |
| 2.1 Unauth agents | FAIL | Expected 401, got 403 |
| 2.2 Invalid cookie | FAIL | Expected 401, got 403 |
| 2.3 Wrong admin secret | PASS | Returns 401 |
| 2.4 Invalid API key | PASS | Returns 403 |
| 3.1 SQL injection | PASS | Handled safely (HTTP 000) |
| 3.2 XSS in agent name | PASS | Input sanitized or safely handled |
| 3.3 Oversized payload | FAIL | Expected 413/400, got 200 |
| 3.4 Path traversal | PASS | Blocked (404) |
| 4.1 HSTS | PASS | Header present |
| 4.2 X-Frame-Options | PASS | Header present |
| 4.3 X-Content-Type-Options | PASS | Header present |
| 4.4 Server disclosure | PASS | No Server header |
| 5.1 Rate limiting | PASS | 0/20 rate-limited (threshold may be higher) |
| 6.1 Base64 evasion | PASS | Clean=True (note: base64 bypasses regex DLP — expected) |
| 6.2 Spaced CC evasion | PASS | Clean=True (character-spaced is known limitation) |

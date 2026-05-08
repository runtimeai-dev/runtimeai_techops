# Test 5: Audit Chain & Compliance
Date: Fri Mar 27 18:05:34 PDT 2026
Tenant: equinix-test

## 5.1 Verify Audit Chain Integrity
```json
{"message":"Chain integrity verified. All hashes are valid.","valid":true}

```
## 5.2 List Audit Evidence
```json
[{"action":"create_egress_policy","actor":"equinix-test-admin","decision":"","hash":"daaa07507d648aa91b407894dce62731c5104b9782779c984afe7208b089f2e7","id":"69189735-fa6c-4365-84fc-5abd4ad08531","metadata":{"action":"block","category":"ai-vendor"},"resource":"*.openai.com","timestamp":"2026-03-28T01:04:47.935426Z","type":"audit_event"},{"action":"create_agent","actor":"equinix-test-admin","decision":"","hash":"b67c5341aad733266566f56ff3bce99362309daccb3559314c0be94aedf9a1aa","id":"db1c98b0-7983-4b1a-931b-c927362bb145","metadata":{"name":"eqx-payment-agent"},"resource":"az-agent-ftalnlei4q3lee81","timestamp":"2026-03-28T01:04:11.255261Z","type":"audit_event"},{"action":"login","actor":"equinix-test-admin","decision":"","hash":"89f7ae12d9cd3c0a8d340f97bdf9dc05edf6c7433d712243d3cbbcae17f5a7d8","id":"f91313d7-c5e9-42ce-9842-99a558784dee","metadata":{"method":"password"},"resource":"dashboard","timestamp":"2026-03-28T01:03:48.332968Z","type":"audit_event"},{"action":"tenant_created","actor":"system","decision":"","hash":"a9847e107a3c04e7561b41553e390ad6b17120f5fa287b6fd953ff6506cbcd4f","id":"51786bcc-d601-4c2a-8a24-19589d02cdb8","metadata":{},"resource":"tenant","timestamp":"2026-03-28T01:02:16.671918Z","type":"audit_event"},{"action":"onboard_tenant","actor":"admin-secret-auth","decision":"","hash":"e12ba8785cf433b864ca873266c882d46fc83f058447e1eae840bb10f2054d91","id":"6fe539c7-5ede-49f4-8a35-78ca5e1faee3","metadata":{"actor_role":"admin","admin_email":"admin@equinix-test.com","ip_address":"10.0.1.63:59828","resource_id":"equinix-test","resource_type":"tenant"},"resource":"tenant:equinix-test","timestamp":"2026-03-28T01:02:16.662359Z","type":"audit_event"}]

```
## 5.3 Export Evidence (JSON)
```json
[{"action":"create_egress_policy","actor":"equinix-test-admin","decision":"","hash":"daaa07507d648aa91b407894dce62731c5104b9782779c984afe7208b089f2e7","id":"69189735-fa6c-4365-84fc-5abd4ad08531","metadata":{"action":"block","category":"ai-vendor"},"resource":"*.openai.com","timestamp":"2026-03-28T01:04:47.935426Z","type":"audit_event"},{"action":"create_agent","actor":"equinix-test-admin","decision":"","hash":"b67c5341aad733266566f56ff3bce99362309daccb3559314c0be94aedf9a1aa","id":"db1c98b0-7983-4b1a-931b-c927362bb145","metadata":{"name":"eqx-payment-agent"},"resource":"az-agent-ftalnlei4q3lee81","timestamp":"2026-03-28T01:04:11.255261Z","type":"audit_event"},{"action":"login","actor":"equinix-test-admin","decision":"","hash":"89f7ae12d9cd3c0a8d340f97bdf9dc05edf6c7433d712243d3cbbcae17f5a7d8","id":"f91313d7-c5e9-42ce-9842-99a558784dee","metadata":{"method":"password"},"resource":"dashboard","timestamp":"2026-03-28T01:03:48.332968Z","type":"audit_event"},{"action":"tenant_created","actor":"system","decision":"","hash":"a9847e107a3c04e7561b41553e390ad6b17120f5fa287b6fd953ff6506cbcd4f","id":"51786bcc-d601-4c2a-8a24-19589d02cdb8","metadata":{},"resource":"tenant","timestamp":"2026-03-28T01:02:16.671918Z","type":"audit_event"},{"action":"onboard_tenant","actor":"admin-secret-auth","decision":"","hash":"e12ba8785cf433b864ca873266c882d46fc83f058447e1eae840bb10f2054d91","id":"6fe539c7-5ede-49f4-8a35-78ca5e1faee3","metadata":{"actor_role":"admin","admin_email":"admin@equinix-test.com","ip_address":"10.0.1.63:59828","resource_id":"equinix-test","resource_type":"tenant"},"resource":"tenant:equinix-test","timestamp":"2026-03-28T01:02:16.662359Z","type":"audit_event"}]

```
## 5.4 List Compliance Frameworks
```json
{"frameworks":[{"id":"846e2bc2-6e0a-4b9b-9a26-d3e7dce5a146","tenant_id":"equinix-test","framework_id":"eu-ai-act","framework_name":"EU AI Act","is_custom":false,"created_at":"2026-03-28T01:02:16.678061Z"},{"id":"9654c962-c6c6-478c-9cb2-511faae02d59","tenant_id":"equinix-test","framework_id":"gdpr","framework_name":"GDPR","is_custom":false,"created_at":"2026-03-28T01:02:16.678061Z"},{"id":"8ae05ee5-4732-49ce-8f1b-9921c907499b","tenant_id":"equinix-test","framework_id":"soc2-type-ii","framework_name":"SOC 2 Type II","is_custom":false,"created_at":"2026-03-28T01:02:16.678061Z"}]}

```
## 5.5 Get Compliance Evidence
```json
404 page not found

```

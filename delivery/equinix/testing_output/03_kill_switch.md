# Test 3: Kill Switch
Date: Fri Mar 27 18:04:48 PDT 2026
Tenant: equinix-test

## 3.1 Activate Kill Switch
```json
{"status":"activated"}

```
## 3.2 List Active Kill Switches
```json
{"runtimeai:killswitch:active:agent:az-agent-ftalnlei4q3lee81":{"action":"KILL","scope":"agent","target":"az-agent-ftalnlei4q3lee81","reason":"Anomalous behavior detected - P2 test","duration":"10m0s","timestamp":"2026-03-28T01:04:48.396017442Z"},"runtimeai:killswitch:active:agent:eqx-local-ollama-SY4":{"action":"KILL","scope":"agent","target":"eqx-local-ollama-SY4","reason":"exfil to openai","duration":"0s","timestamp":"2026-03-24T09:29:19.586224907Z"}}

```
## 3.3 Deactivate Kill Switch
```json
{"status":"deactivated"}

```
## 3.4 Verify Deactivated
```json
{"runtimeai:killswitch:active:agent:eqx-local-ollama-SY4":{"action":"KILL","scope":"agent","target":"eqx-local-ollama-SY4","reason":"exfil to openai","duration":"0s","timestamp":"2026-03-24T09:29:19.586224907Z"}}

```

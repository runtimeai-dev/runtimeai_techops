# Test 8: Identity Fabric & MCP (Corrected Paths)
Date: Fri Mar 27 18:05:48 PDT 2026
Tenant: equinix-test

## 8.1 MCP Servers (with trailing slash)
```json
404 page not found

```
## 8.2 MCP Tools (with trailing slash)
```json
{"tools":[]}

```
## 8.3 Identity DNS Health
```json
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "b76e01d4afb83cc2ba8db7f6a39edcbb356b65497fa61de19e34961ac954575d": OCI runtime exec failed: exec failed: unable to start container process: exec: "curl": executable file not found in $PATH: unknown

```
## 8.4 ML Intelligence Health
```json
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "0c2120ce6bfa455f7a3cb1e3e6e571d1dbb3ec23dfac996babce57c62daaa049": OCI runtime exec failed: exec failed: unable to start container process: exec: "curl": executable file not found in $PATH: unknown

```
## 8.5 Service-to-Service Health (internal)
### flow-enforcer
```
Not reachable or no healthz endpoint

```
### data-proxy
```
Not reachable or no healthz endpoint

```
### drift-engine
```
Not reachable or no healthz endpoint

```
### cost-ledger
```
Not reachable or no healthz endpoint

```
### vendor-wrapper
```
Not reachable or no healthz endpoint

```
### bot-ca
```
Not reachable or no healthz endpoint

```
### network-analyzer
```
Not reachable or no healthz endpoint

```

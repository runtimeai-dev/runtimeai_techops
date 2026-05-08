# RuntimeAI Data Plane (DP) & Control Plane (CP) Separation

This directory contains the verification suite for deploying the RuntimeAI platform across dedicated nodes representing separated Control Plane (CP) and Data Plane (DP) architectures using Azure AKS node pools.

## Objectives
- Deploy the platform where DP intensive processors (ML Intelligence, Network Analyzer, WAF) do not consume resources allocated to CP apps (Dashboard, Auth, PostgreSQL).
- Validate discovery and agent registration on separated CP/DP architectures using real-world testing (SDK/CLI equivalents).
- Verify 100% strict node separation across the deployment topologies.

## Components

1. **`setup_2nodes.sh`** 
   - Uses `az aks` to create an initial cluster `cp-tier` and secondary `dp-tier`.
   - Runs `helm install` natively, executing continuous `kubectl patch deployment` directives to strictly set `nodeSelector` properties in real-time, enforcing the separation.

2. **`verify_node_separation.sh`**
   - Discovers nodes based on labels `runtimeai-tier=cp` and `runtimeai-tier=dp`.
   - Crawls all 27+ microservices mapped against the known core definitions, flagging if any DP instances (e.g., flow-enforcer) stray into CP territory, and vice versa.

3. **`dp_realworld_tests.sh`**
   - The functional validation test suite simulating SDK/CLI patterns. 
   - Proves that discovery components route correctly to DPI pods, tests Firewall overrides, provisions local AI agents, and simulates Drift behavioral intercepts fully constrained to DP infrastructure boundaries.

## Quick Start
```bash
./setup_2nodes.sh
./verify_node_separation.sh
./dp_realworld_tests.sh
```

# eBPF Network Tap — Fully SaaS Deployment Guide

> **Version**: 1.0.0
> **Last Updated**: 2026-04-16
> **Target Environment**: RuntimeAI Fully SaaS (api.rt19.runtimeai.io)
> **Minimum Requirements**: Linux kernel 4.15+, root access, curl
> **Depends On**: OPER_RT19-058 (sidecar + eBPF infrastructure)

---

## Overview

The RuntimeAI eBPF Network Tap passively monitors all network traffic on a Linux host to detect LLM API calls without installing agents on individual workloads. It uses eBPF (extended Berkeley Packet Filter) to hook into the kernel's networking stack at near-zero overhead.

### What Gets Detected

| Traffic Pattern | Detection Method |
|----------------|------------------|
| HTTPS connections to `api.openai.com` | TLS SNI (Server Name Indication) extraction |
| HTTPS connections to `api.anthropic.com` | TLS SNI extraction |
| AWS Bedrock API calls | Destination IP range + TLS SNI |
| Azure OpenAI calls | TLS SNI pattern `*.openai.azure.com` |
| Google Vertex AI calls | TLS SNI to `generativelanguage.googleapis.com` |
| Any connection to 20+ known LLM domains | Domain pattern matching |

### How It Works

```
Linux kernel → eBPF TC hook (ingress/egress)
    → Extract TLS ClientHello SNI
    → Match against LLM domain list
    → Emit structured event via perf buffer
    → Userspace agent → POST /api/dataplane/heartbeat → RuntimeAI CP
```

---

## Prerequisites

1. **Linux kernel 4.15+** (Ubuntu 18.04+, RHEL 8+, Debian 10+, Amazon Linux 2)
   ```bash
   uname -r   # Must be >= 4.15
   ```
2. **Root access** (eBPF requires `CAP_SYS_ADMIN` or `CAP_BPF` on kernel 5.8+)
3. **Internet access** to `api.rt19.runtimeai.io` (port 443)
4. **Tenant credentials**: Tenant ID + API Key

### Kernel Version Compatibility

| Kernel | Support Level | Notes |
|--------|--------------|-------|
| 4.15–4.19 | Basic | TC hook only, limited features |
| 5.0–5.7 | Full | All features, requires CAP_SYS_ADMIN |
| 5.8+ | Full | CAP_BPF sufficient (no full root needed) |
| 6.0+ | Optimal | BTF support, CO-RE (Compile Once, Run Everywhere) |

---

## Installation

### Method 1: One-Line Install (Recommended)

```bash
curl -sSL https://api.rt19.runtimeai.io/api/discovery/client_agents/ebpf_installer.sh | \
  sudo TENANT_ID=<your-tenant-id> API_KEY=<your-api-key> bash
```

### Method 2: Manual Install

```bash
# 1. Download the eBPF tap binary
sudo mkdir -p /opt/runtimeai/ebpf
curl -sSL https://api.rt19.runtimeai.io/api/discovery/client_agents/ebpf_tap \
  -o /opt/runtimeai/ebpf/runtimeai-tap
chmod +x /opt/runtimeai/ebpf/runtimeai-tap

# 2. Create config
cat <<EOF | sudo tee /etc/runtimeai/ebpf-tap.yaml
tenant_id: "<your-tenant-id>"
api_key: "<your-api-key>"
api_url: "https://api.rt19.runtimeai.io"
interface: "eth0"          # Network interface to monitor (use 'any' for all)
heartbeat_interval: 60     # Report metrics every 60 seconds
EOF

# 3. Run
sudo /opt/runtimeai/ebpf/runtimeai-tap --config /etc/runtimeai/ebpf-tap.yaml
```

### Method 3: systemd Service (Production)

```bash
sudo tee /etc/systemd/system/runtimeai-ebpf-tap.service <<EOF
[Unit]
Description=RuntimeAI eBPF Network Tap
After=network.target

[Service]
Type=simple
ExecStart=/opt/runtimeai/ebpf/runtimeai-tap --config /etc/runtimeai/ebpf-tap.yaml
Restart=always
RestartSec=10
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now runtimeai-ebpf-tap
```

---

## Expected Output

```
[runtimeai-tap] Loading eBPF program...
[runtimeai-tap] Attached TC hook to eth0 (ingress + egress)
[runtimeai-tap] Monitoring for LLM API traffic (20 domain patterns)
[runtimeai-tap] Heartbeat → api.rt19.runtimeai.io (tenant: <id>)
[runtimeai-tap] Detected: api.openai.com (10.0.1.42 → 104.18.7.57, 4.2KB)
[runtimeai-tap] Detected: api.anthropic.com (10.0.1.42 → 104.18.32.7, 12.1KB)
[runtimeai-tap] Heartbeat: 47 events/min, 2 LLM calls detected
```

---

## Dashboard Verification

1. Log into `https://app.rt19.runtimeai.io`
2. Navigate to **Data Plane → Health** — verify the eBPF tap appears with "active" status
3. Navigate to **Discovery → Shadow AI Inbox** — filter by `source: ebpf_tap`
4. LLM API call findings will appear with the source IP, destination, and byte count

---

## Performance Impact

| Metric | Typical Impact |
|--------|---------------|
| CPU overhead | < 1% (eBPF runs in kernel, no context switch) |
| Memory | ~20MB for the userspace agent + 4MB for eBPF maps |
| Network latency | Zero (passive tap, not inline) |
| Disk | None (no local storage, events streamed to CP) |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `eBPF program failed to load` | Check kernel version: `uname -r` must be >= 4.15 |
| `Permission denied` | Run as root or with `CAP_BPF` capability |
| `No LLM calls detected` | Check interface name: `ip link show` — use the correct NIC |
| `Heartbeat failed: 401` | Verify TENANT_ID and API_KEY in config |
| `LimitMEMLOCK too low` | Add `LimitMEMLOCK=infinity` to systemd unit |
| Only seeing IP addresses, not domains | TLS SNI extraction requires TCP stream reassembly — ensure packets aren't truncated |

---

## Security Considerations

- eBPF tap is **read-only** — it cannot modify, drop, or inject packets
- Only TLS SNI (domain name) is extracted from ClientHello — no payload inspection
- eBPF program is verified by the kernel verifier before loading (cannot crash the kernel)
- API Key is stored in the config file — protect with `chmod 600`
- All heartbeat data transmitted over TLS (HTTPS)

---

## Uninstall

```bash
sudo systemctl stop runtimeai-ebpf-tap
sudo systemctl disable runtimeai-ebpf-tap
sudo rm /etc/systemd/system/runtimeai-ebpf-tap.service
sudo rm -rf /opt/runtimeai/ebpf /etc/runtimeai/ebpf-tap.yaml
sudo systemctl daemon-reload
```

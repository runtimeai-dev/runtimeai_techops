#!/bin/bash
# 24_gaming_test.sh - Verify Gaming Anti-Cheat Verifier

set -e

VERIFIER_URL="http://localhost:8104"

echo "--- Feature 24: Gaming Anti-Cheat Verification ---"

# 1. Valid Agent (NPC)
echo "1. Testing Authorized Bot (Attested)..."
curl -s -X POST "$VERIFIER_URL/verify" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "npc-bot-42",
    "game_id": "nexus-siege",
    "attestation": {
      "tpm_quote": "SGVsbG8gV29ybGQgLSBUUE0gUXVvdGUgU2ltdWxhdGlvbiB3aXRoIGVub3VnaCBsZW5ndGggdG8gcGFzcyBoYXJkZW5lZCBjaGVja3MuLi4K",
      "pcr_values": "AAAA",
      "process_hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    },
    "input_telemetry": {
      "mouse_movements": [
        {"x": 10, "y": 10, "t": 0},
        {"x": 20, "y": 25, "t": 100}
      ]
    }
  }' | jq

# 2. Malicious Bot (Linear Movement, No Attestation)
echo "2. Testing Malicious Bot (Detection)..."
curl -s -X POST "$VERIFIER_URL/verify" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "unknown-cheater",
    "game_id": "nexus-siege",
    "attestation": {},
    "input_telemetry": {
      "mouse_movements": [
        {"x": 0, "y": 0, "t": 0},
        {"x": 10, "y": 10, "t": 10},
        {"x": 20, "y": 20, "t": 20}
      ],
      "reaction_time_avg_ms": 20,
      "key_intervals_ms": [10, 10, 10, 10]
    }
  }' | jq

echo "--- Gaming Anti-Cheat Verification Complete ---"

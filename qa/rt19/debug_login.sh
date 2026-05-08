#!/bin/bash
echo "Testing Login for a-admin@${TENANT_ID:-bank-a}.local..."
curl -v -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "${TENANT_ID:-bank-a}", "email": "a-admin@${TENANT_ID:-bank-a}.local", "password": "password123"}'
echo ""

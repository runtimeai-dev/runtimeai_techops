#!/bin/bash
echo "Testing Discovery API Access..."
# Test 1: Direct path (What the code currently is)
echo "1. GET /tools (Expected: 200/403/401, Current Code Path)"
curl -v -H "X-Tenant-ID: ${TENANT_ID:-bank-a}" http://localhost:8080/tools

# Test 2: API Path (What the frontend uses)
echo ""
echo "2. GET /api/tools (Expected: 404 if not handled)"
curl -v -H "X-Tenant-ID: ${TENANT_ID:-bank-a}" http://localhost:8080/api/tools
echo ""

# Test 3: Discovered Agents (Dashboard Endpoint)
echo "3. GET /api/inventory/discovered (Expected: 200 JSON)"
# We need a cookie for this one because it uses requireSession
# Let's try to just check if it exists (401 Unauthorized is good enough proof it's handled)
curl -v -H "X-Tenant-ID: ${TENANT_ID:-bank-a}" http://localhost:8080/api/inventory/discovered
echo ""

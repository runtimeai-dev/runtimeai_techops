#!/bin/bash
# Comprehensive MSFT Backend API Tests
# Tests for MSFT-35, 36, 38, 40

source "$(dirname "$0")/common.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "MSFT Comprehensive Backend API Tests"
echo "=========================================="

# Get current user ID for sponsor tests
USER_ID=$(auth_curl $CONTROL_PLANE_URL/api/auth/me | jq -r '.user.user_id')
echo "Using User ID: $USER_ID"

# ===== MSFT-35: Governance/Sponsors Tests =====
echo ""
echo "Testing MSFT-35 (Governance/Sponsors)..."

# Create test agent for sponsor tests
AGENT_ID=$(create_agent "Sponsor Test Agent")
echo "  - Created test agent: $AGENT_ID"

# 35.1 List sponsors (should be empty initially)
echo -n "  - List Sponsors (GET /api/agents/:id/sponsors): "
SPONSORS_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/agents/$AGENT_ID/sponsors")
if echo "$SPONSORS_RESP" | jq -e 'type == "array"' > /dev/null 2>&1; then
    COUNT=$(echo "$SPONSORS_RESP" | jq '. | length')
    echo -e "${GREEN}PASS${NC} (Count: $COUNT)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $SPONSORS_RESP"
    exit 1
fi

# 35.2 Assign sponsor
echo -n "  - Assign Sponsor (POST /api/agents/:id/sponsors): "
ASSIGN_RESP=$(auth_curl -H "Content-Type: application/json" \
  -d "{\"user_id\":\"$USER_ID\",\"role\":\"sponsor\",\"is_primary\":true}" \
  "$CONTROL_PLANE_URL/api/agents/$AGENT_ID/sponsors" -w "%{http_code}")
HTTP_CODE=$(echo "$ASSIGN_RESP" | tail -c 4)
if [ "$HTTP_CODE" == "201" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} (Code: $HTTP_CODE)"
    exit 1
fi

# 35.3 List sponsors (verify added)
echo -n "  - Verify Sponsor Added: "
SPONSORS_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/agents/$AGENT_ID/sponsors")
COUNT=$(echo "$SPONSORS_RESP" | jq '. | length')
if [ "$COUNT" -eq 1 ]; then
    echo -e "${GREEN}PASS${NC} (Count: $COUNT)"
else
    echo -e "${RED}FAIL${NC} (Expected 1, got $COUNT)"
    exit 1
fi

# 35.4 Update sponsor role
echo -n "  - Update Sponsor (PATCH /api/agents/:id/sponsors/:user_id): "
UPDATE_RESP=$(auth_curl -X PATCH -H "Content-Type: application/json" \
  -d "{\"role\":\"owner\",\"is_primary\":true}" \
  "$CONTROL_PLANE_URL/api/agents/$AGENT_ID/sponsors/$USER_ID")
if echo "$UPDATE_RESP" | jq -e '.status == "updated"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $UPDATE_RESP"
    exit 1
fi

# 35.5 List my agents
echo -n "  - List My Agents (GET /api/sponsors/my-agents): "
MY_AGENTS_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/sponsors/my-agents")
if echo "$MY_AGENTS_RESP" | jq -e '.agent_ids | type == "array"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $MY_AGENTS_RESP"
    exit 1
fi

# 35.6 Remove sponsor
echo -n "  - Remove Sponsor (DELETE /api/agents/:id/sponsors/:user_id): "
REMOVE_RESP=$(auth_curl -X DELETE "$CONTROL_PLANE_URL/api/agents/$AGENT_ID/sponsors/$USER_ID")
if echo "$REMOVE_RESP" | jq -e '.status == "removed"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $REMOVE_RESP"
    exit 1
fi

echo -e "${GREEN}✓ All MSFT-35 Sponsor Tests PASSED${NC}"

# ===== MSFT-36: Blueprints Tests =====
echo ""
echo "Testing MSFT-36 (Blueprints)..."

# 36.1 List blueprints
echo -n "  - List Blueprints (GET /api/blueprints): "
BP_LIST_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/blueprints")
if echo "$BP_LIST_RESP" | jq -e '.blueprints | type == "array"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $BP_LIST_RESP"
    exit 1
fi

# 36.2 Create blueprint
echo -n "  - Create Blueprint (POST /api/blueprints): "
BP_NAME="Test-Blueprint-$(date +%s)"
BP_CREATE_RESP=$(auth_curl -H "Content-Type: application/json" \
  -d "{\"name\":\"$BP_NAME\",\"description\":\"Test blueprint\",\"max_budget_monthly\":1000}" \
  "$CONTROL_PLANE_URL/api/blueprints")
BP_ID=$(echo "$BP_CREATE_RESP" | jq -r '.id')
if [ "$BP_ID" != "null" ] && [ -n "$BP_ID" ]; then
    echo -e "${GREEN}PASS${NC} (ID: $BP_ID)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $BP_CREATE_RESP"
    exit 1
fi

# 36.3 Get blueprint detail
echo -n "  - Get Blueprint Detail (GET /api/blueprints/:id): "
BP_GET_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/blueprints/$BP_ID")
if echo "$BP_GET_RESP" | jq -e '.id' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $BP_GET_RESP"
    exit 1
fi

# 36.4 Update blueprint
echo -n "  - Update Blueprint (PATCH /api/blueprints/:id): "
BP_UPDATE_RESP=$(auth_curl -X PATCH -H "Content-Type: application/json" \
  -d "{\"name\":\"$BP_NAME-Updated\",\"description\":\"Updated description\"}" \
  "$CONTROL_PLANE_URL/api/blueprints/$BP_ID")
if echo "$BP_UPDATE_RESP" | jq -e '.status == "updated"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $BP_UPDATE_RESP"
    exit 1
fi

# 36.5 Archive blueprint
echo -n "  - Archive Blueprint (DELETE /api/blueprints/:id): "
BP_ARCHIVE_RESP=$(auth_curl -X DELETE "$CONTROL_PLANE_URL/api/blueprints/$BP_ID")
if echo "$BP_ARCHIVE_RESP" | jq -e '.status == "archived"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $BP_ARCHIVE_RESP"
    exit 1
fi

echo -e "${GREEN}✓ All MSFT-36 Blueprint Tests PASSED${NC}"

# ===== MSFT-38: Metadata Tests =====
echo ""
echo "Testing MSFT-38 (Agent Metadata)..."

# Create test agent for metadata tests
META_AGENT_ID=$(create_agent "Metadata Test Agent")
echo "  - Created test agent: $META_AGENT_ID"

# 38.1 Get manifest (baseline)
echo -n "  - Get Manifest Baseline (GET /api/agents/:id/manifest): "
MANIFEST_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/agents/$META_AGENT_ID/manifest")
if echo "$MANIFEST_RESP" | jq -e '.id' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $MANIFEST_RESP"
    exit 1
fi

# 38.2 Update agent metadata
echo -n "  - Update Metadata (PATCH /api/agents/:id): "
META_UPDATE_RESP=$(auth_curl -X PATCH -H "Content-Type: application/json" \
  -d '{"description":"Updated agent description","version":"2.0.0","tags":["test","updated"]}' \
  "$CONTROL_PLANE_URL/api/agents/$META_AGENT_ID")
if echo "$META_UPDATE_RESP" | jq -e '.status == "updated"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $META_UPDATE_RESP"
    exit 1
fi

# 38.3 Get manifest (verify updated)
echo -n "  - Verify Metadata Updated: "
MANIFEST_UPDATED=$(auth_curl "$CONTROL_PLANE_URL/api/agents/$META_AGENT_ID/manifest")
VERSION=$(echo "$MANIFEST_UPDATED" | jq -r '.version')
if [ "$VERSION" == "2.0.0" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} (Expected 2.0.0, got $VERSION)"
    exit 1
fi

echo -e "${GREEN}✓ All MSFT-38 Metadata Tests PASSED${NC}"

# ===== MSFT-40: Entitlements Tests =====
echo ""
echo "Testing MSFT-40 (Entitlements)..."

# 40.1 List access packages
echo -n "  - List Access Packages (GET /api/access-packages): "
PKG_LIST_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/access-packages")
if echo "$PKG_LIST_RESP" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $PKG_LIST_RESP"
    exit 1
fi

# 40.2 Create access package
echo -n "  - Create Access Package (POST /api/access-packages): "
PKG_NAME="Test-Package-$(date +%s)"
PKG_CREATE_RESP=$(auth_curl -H "Content-Type: application/json" \
  -d "{\"name\":\"$PKG_NAME\",\"description\":\"Test package\",\"default_duration_days\":30,\"max_duration_days\":90}" \
  "$CONTROL_PLANE_URL/api/access-packages")
PKG_ID=$(echo "$PKG_CREATE_RESP" | jq -r '.id')
if [ "$PKG_ID" != "null" ] && [ -n "$PKG_ID" ]; then
    echo -e "${GREEN}PASS${NC} (ID: $PKG_ID)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $PKG_CREATE_RESP"
    exit 1
fi

# 40.3 Get package detail
echo -n "  - Get Package Detail (GET /api/access-packages/:id): "
PKG_GET_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/access-packages/$PKG_ID")
if echo "$PKG_GET_RESP" | jq -e '.id' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $PKG_GET_RESP"
    exit 1
fi

# 40.4 Assign package to agent
ENT_AGENT_ID=$(create_agent "Entitlement Test Agent")
echo "  - Created test agent: $ENT_AGENT_ID"

echo -n "  - Assign Package (POST /api/access-packages/:id/assign): "
ASSIGN_PKG_RESP=$(auth_curl -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"$ENT_AGENT_ID\",\"justification\":\"Test assignment\"}" \
  "$CONTROL_PLANE_URL/api/access-packages/$PKG_ID/assign")
ASSIGNMENT_ID=$(echo "$ASSIGN_PKG_RESP" | jq -r '.assignment_id')
if [ "$ASSIGNMENT_ID" != "null" ] && [ -n "$ASSIGNMENT_ID" ]; then
    echo -e "${GREEN}PASS${NC} (Assignment ID: $ASSIGNMENT_ID)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $ASSIGN_PKG_RESP"
    exit 1
fi

# 40.5 List assignments
echo -n "  - List Assignments (GET /api/access-packages/:id/assignments): "
ASSIGNMENTS_RESP=$(auth_curl "$CONTROL_PLANE_URL/api/access-packages/$PKG_ID/assignments")
if echo "$ASSIGNMENTS_RESP" | jq -e 'type == "array"' > /dev/null 2>&1; then
    COUNT=$(echo "$ASSIGNMENTS_RESP" | jq '. | length')
    echo -e "${GREEN}PASS${NC} (Count: $COUNT)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $ASSIGNMENTS_RESP"
    exit 1
fi

# 40.6 Update package
echo -n "  - Update Package (PATCH /api/access-packages/:id): "
PKG_UPDATE_RESP=$(auth_curl -X PATCH -H "Content-Type: application/json" \
  -d "{\"name\":\"$PKG_NAME-Updated\",\"description\":\"Updated package\"}" \
  "$CONTROL_PLANE_URL/api/access-packages/$PKG_ID")
if echo "$PKG_UPDATE_RESP" | jq -e '.status == "updated"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $PKG_UPDATE_RESP"
    exit 1
fi

# 40.7 Archive package
echo -n "  - Archive Package (DELETE /api/access-packages/:id): "
PKG_ARCHIVE_RESP=$(auth_curl -X DELETE "$CONTROL_PLANE_URL/api/access-packages/$PKG_ID")
if echo "$PKG_ARCHIVE_RESP" | jq -e '.status == "archived"' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Response: $PKG_ARCHIVE_RESP"
    exit 1
fi

echo -e "${GREEN}✓ All MSFT-40 Entitlement Tests PASSED${NC}"

echo ""
echo "=========================================="
echo "ALL MSFT COMPREHENSIVE TESTS PASSED"
echo "=========================================="

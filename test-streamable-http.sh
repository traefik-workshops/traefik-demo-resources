#!/bin/bash

BASE_URL="https://mcp-gov.kubeata.traefikhub.dev/mcp"

echo "=== Testing MCP Streamable HTTP (JSON) ==="

# Helper function to send MCP request and get JSON response
mcp_call() {
  local method=$1
  local params=$2
  local id=$3
  
  curl -s -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"$method\",\"params\":$params}"
}

# Test 1: List tools
echo -e "\n=== 1. Listing Tools ==="
mcp_call "tools/list" "{}" 1 | jq -r '.result.tools[] | "- \(.name): \(.description)"'

# Test 2: Ping
echo -e "\n=== 2. Testing Ping ==="
mcp_call "tools/call" '{"name":"ping","arguments":{}}' 2 | jq -r '.result'

# Test 3: List Areas
echo -e "\n=== 3. List Areas ==="
mcp_call "tools/call" '{"name":"list_areas","arguments":{}}' 3 | jq -r '.result'

# Test 4: Emergency Status Summary
echo -e "\n=== 4. Emergency Status Summary ==="
mcp_call "tools/call" '{"name":"emergency_status_summary","arguments":{}}' 4 | jq -r '.result'

# Test 5: Rescue Mission
echo -e "\n=== 5. Rescue Mission (Downtown) ==="
mcp_call "tools/call" '{"name":"rescue_mission","arguments":{"area":"downtown","incident_type":"all"}}' 5 | jq -r '.result'

echo -e "\n=== ✅ Test Complete ==="

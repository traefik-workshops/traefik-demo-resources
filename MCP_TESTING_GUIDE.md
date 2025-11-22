# MCP Server Testing Guide

This guide provides comprehensive test prompts for both Government and Higher-Ed MCP servers, including examples that trigger policy decisions.

## Prerequisites

Before testing, ensure the MCP servers are deployed with the updated policies:

```bash
# Deploy or update the services
helm upgrade --install gov ./gov/helm -n gov --create-namespace
helm upgrade --install higher-ed ./higher-ed/helm -n higher-ed --create-namespace

# Verify pods are running
kubectl get pods -n gov
kubectl get pods -n higher-ed

# Check MCP server logs
kubectl logs -n gov -l app=gov-mcp-server -f
kubectl logs -n higher-ed -l app=higher-ed-mcp-server -f
```

## Important: MCP Protocol Requirements

The MCP gateway policies must allow three types of requests:
1. **`initialize`** - Protocol handshake
2. **`tools/list`** - Discover available tools
3. **`tools/call`** - Execute specific tools

If you see **404 errors**, the policies are likely blocking the initial handshake. Both MCP servers now include policies for all three request types.

## Table of Contents
- [Government Services MCP](#government-services-mcp)
- [Higher Education Services MCP](#higher-education-services-mcp)
- [Policy Testing Scenarios](#policy-testing-scenarios)

---

## Government Services MCP

### 1. Browse Operations (List All)

#### 1.1 List All Road Closures
**Test Prompt:**
```
Show me all the current road closures in the city
```
**Expected Tool:** `list_all_road_closures`
**Policy:** ✅ Allowed (read-only operation)

#### 1.2 List All Police Incidents
**Test Prompt:**
```
What active police incidents are happening right now?
```
**Expected Tool:** `list_all_incidents`
**Policy:** ✅ Allowed (read-only operation)

#### 1.3 List All Power Outages
**Test Prompt:**
```
Are there any power outages affecting the city?
```
**Expected Tool:** `list_all_outages`
**Policy:** ✅ Allowed (read-only operation)

#### 1.4 List All Infrastructure Status
**Test Prompt:**
```
Give me a status report on all critical infrastructure
```
**Expected Tool:** `list_all_infrastructure`
**Policy:** ✅ Allowed (read-only operation)

#### 1.5 List All Dams
**Test Prompt:**
```
What's the status of all our dam floodgates?
```
**Expected Tool:** `list_all_dams`
**Policy:** ✅ Allowed (read-only operation)

#### 1.6 List All Areas
**Test Prompt:**
```
Which areas are being monitored in our emergency system?
```
**Expected Tool:** `list_areas`
**Policy:** ✅ Allowed (read-only operation)

---

### 2. Detail Lookup Operations

#### 2.1 Get Road Closure Details
**Test Prompt:**
```
Tell me more about the closure on Main Street
```
**Expected Tool:** `get_road_closure_details` with `street_name: "Main Street"`
**Policy:** ✅ Allowed (read-only detail lookup)

#### 2.2 Get Incident Details
**Test Prompt:**
```
What are the details of incident INC-2024-1547?
```
**Expected Tool:** `get_incident_details` with `incident_id: "INC-2024-1547"`
**Policy:** ✅ Allowed (read-only detail lookup)

#### 2.3 Get Outage Details
**Test Prompt:**
```
Is there a power outage at Downtown Plaza?
```
**Expected Tool:** `get_outage_details` with `location: "Downtown Plaza"`
**Policy:** ✅ Allowed (read-only detail lookup)

#### 2.4 Get Dam Status
**Test Prompt:**
```
What's the current status of the northern dam?
```
**Expected Tool:** `get_dam_status` with `dam_location: "north_dam"`
**Policy:** ✅ Allowed (read-only detail lookup)

---

### 3. Emergency Analysis Operations

#### 3.1 Emergency Status Summary
**Test Prompt:**
```
Give me an emergency status summary for the downtown area
```
**Expected Tool:** `emergency_status_summary` with `area: "downtown"`
**Policy:** ✅ Allowed (emergency analysis)

#### 3.2 Rescue Mission Analysis
**Test Prompt:**
```
I need to plan a rescue mission to the industrial district. What's the situation there?
```
**Expected Tool:** `rescue_mission` with `target_area: "industrial"`
**Policy:** ✅ Allowed (emergency analysis)

**Complex Test Prompt:**
```
There's a major incident in the residential area. Analyze road access, infrastructure status, and any hazards for a rescue operation.
```
**Expected Tool:** `rescue_mission` with `target_area: "residential"`
**Policy:** ✅ Allowed

---

### 4. Write Operations (Controlled)

#### 4.1 Floodgate Control - ALLOWED
**Test Prompt:**
```
Open the floodgates at the southern dam to prevent flooding downstream. Reason: Heavy rainfall forecast and rising water levels.
```
**Expected Tool:** `floodgate_control` with:
- `dam_location: "south_dam"`
- `action: "open"`
- `reason: "Heavy rainfall forecast and rising water levels"`

**Policy:** ✅ Allowed (requires authorization in production)
**Note:** This is a write operation that modifies infrastructure state.

#### 4.2 Floodgate Control - Close
**Test Prompt:**
```
Close the floodgates at the eastern dam. Reason: Water levels normalized after storm.
```
**Expected Tool:** `floodgate_control` with:
- `dam_location: "east_dam"`
- `action: "close"`
- `reason: "Water levels normalized after storm"`

**Policy:** ✅ Allowed (requires authorization in production)

---

### 5. Discovery Workflows (Multi-Step)

#### 5.1 Find and Investigate Incident
**Test Prompts (sequential):**
```
1. Show me all active incidents
2. Tell me more about the traffic accident incident
3. What's the road status near that incident location?
```
**Expected Tools:**
1. `list_all_incidents`
2. `get_incident_details`
3. `get_road_closure_details`

#### 5.2 Infrastructure Assessment
**Test Prompts (sequential):**
```
1. List all infrastructure in the system
2. Are there any power outages affecting the area?
3. Give me details on the Downtown Plaza outage
```
**Expected Tools:**
1. `list_all_infrastructure`
2. `list_all_outages`
3. `get_outage_details`

---

## Higher Education Services MCP

### 1. Browse Operations (List All)

#### 1.1 List All Financial Aid
**Test Prompt:**
```
Show me all student financial aid records
```
**Expected Tool:** `list_all_financial_aid`
**Policy:** ✅ Allowed (read-only operation)

#### 1.2 List All Scholarships
**Test Prompt:**
```
Which students have scholarship awards?
```
**Expected Tool:** `list_all_scholarships`
**Policy:** ✅ Allowed (read-only operation)

**Search-focused Test Prompt:**
```
I'm looking for students who received the Merit Scholarship. Can you show me all scholarship records?
```
**Expected Tool:** `list_all_scholarships`
**Policy:** ✅ Allowed

#### 1.3 List All Housing
**Test Prompt:**
```
Give me a complete list of all housing units and their occupancy
```
**Expected Tool:** `list_all_housing`
**Policy:** ✅ Allowed (read-only operation)

#### 1.4 List Vacant Housing
**Test Prompt:**
```
What housing units are currently available for assignment?
```
**Expected Tool:** `list_vacant_housing`
**Policy:** ✅ Allowed (read-only operation)

---

### 2. Detail Lookup Operations

#### 2.1 Get Scholarship Status
**Test Prompt:**
```
What scholarships is student S67890 eligible for?
```
**Expected Tool:** `get_scholarship_status` with `student_id: "S67890"`
**Policy:** ✅ Allowed (read-only detail lookup)

#### 2.2 Get Financial Aid Status
**Test Prompt:**
```
Check the financial aid status for student S12345
```
**Expected Tool:** `get_financial_aid_status` with `student_id: "S12345"`
**Policy:** ✅ Allowed (read-only detail lookup)

#### 2.3 Get Housing Unit Details
**Test Prompt:**
```
What are the details of housing unit building-a-101?
```
**Expected Tool:** `get_housing_unit_details` with `unit_id: "building-a-101"`
**Policy:** ✅ Allowed (read-only detail lookup)

---

### 3. Write Operations

#### 3.1 Enroll in Housing - ALLOWED
**Test Prompt:**
```
Enroll student S12345 in housing unit building-b-205
```
**Expected Tool:** `enroll_in_housing` with:
- `unit_id: "building-b-205"`
- `student_id: "S12345"`

**Policy:** ✅ Allowed (enrollment permitted, but requires eligibility checks in production)

#### 3.2 Unenroll from Housing - BLOCKED
**Test Prompt:**
```
Remove student S12345 from their housing assignment
```
**Expected Tool:** `unenroll_from_housing`
**Policy:** ❌ DENIED - Sensitive operation requiring manual admin approval

**Policy Response:**
```
Error: This operation is not allowed. Housing unenrollment requires manual admin approval through proper channels.
```

---

### 4. Discovery Workflows (Multi-Step)

#### 4.1 Find Student and Check Aid
**Test Prompts (sequential):**
```
1. Show me all financial aid records
2. Check the financial aid status for student S12345
3. What scholarships is student S12345 eligible for?
```
**Expected Tools:**
1. `list_all_financial_aid`
2. `get_financial_aid_status`
3. `get_scholarship_status`

#### 4.2 Find Housing and Assign
**Test Prompts (sequential):**
```
1. What housing units are currently vacant?
2. Show me details for unit building-a-101
3. Enroll student S67890 in building-a-101
```
**Expected Tools:**
1. `list_vacant_housing`
2. `get_housing_unit_details`
3. `enroll_in_housing`

**Policy Flow:**
- Steps 1-2: ✅ Allowed (read-only)
- Step 3: ✅ Allowed (write operation permitted)

#### 4.3 Browse Scholarships Then Lookup
**Test Prompts (sequential):**
```
1. List all scholarship records
2. I see student S23456 has multiple scholarships. Tell me more about their scholarship status.
```
**Expected Tools:**
1. `list_all_scholarships`
2. `get_scholarship_status` with `student_id: "S23456"`

---

## Policy Testing Scenarios

### Government Services - Policy Tests

#### ✅ Test 1: All Read Operations Should Pass
**Prompts:**
- "List all road closures"
- "Show me all incidents"
- "What's the infrastructure status?"
- "Get details for Main Street closure"

**Expected:** All requests should be **ALLOWED**

#### ✅ Test 2: Emergency Operations Should Pass
**Prompts:**
- "Emergency status summary for downtown"
- "Plan a rescue mission to the industrial area"

**Expected:** All requests should be **ALLOWED**

#### ✅ Test 3: Write Operations Should Pass (with proper auth)
**Prompt:**
- "Open the northern dam floodgates due to flooding risk"

**Expected:** Request should be **ALLOWED**
**Production Note:** Should verify JWT claims for admin role

#### ❌ Test 4: Undefined Tools Should Fail
**Prompt:**
- "Delete all incident records" (no such tool exists)

**Expected:** Request should be **DENIED** (defaultAction: deny)

---

### Higher Education - Policy Tests

#### ✅ Test 1: All Read Operations Should Pass
**Prompts:**
- "List all scholarships"
- "Show me all housing units"
- "Check financial aid for student S12345"
- "Get details for housing unit building-a-101"

**Expected:** All requests should be **ALLOWED**

#### ✅ Test 2: Housing Enrollment Should Pass
**Prompt:**
- "Enroll student S12345 in building-b-205"

**Expected:** Request should be **ALLOWED**
**Production Note:** Should verify student eligibility

#### ❌ Test 3: Housing Unenrollment Should Fail
**Prompt:**
- "Remove student S12345 from their housing"

**Expected:** Request should be **DENIED**
**Reason:** Explicit policy blocks `unenroll_from_housing` for security

#### ❌ Test 4: Undefined Tools Should Fail
**Prompt:**
- "Delete student S12345's financial aid records" (no such tool exists)

**Expected:** Request should be **DENIED** (defaultAction: deny)

---

## Cross-Cutting Test Scenarios

### Scenario 1: Emergency + Student Services
**Narrative:** Power outage affects campus, need to check housing impact

**Test Prompts:**
```
Government MCP:
1. Are there any power outages in the university district?
2. What's the infrastructure status near the campus?

Higher-Ed MCP:
3. Show me all housing units
4. Which students might be affected in buildings A and B?
```

### Scenario 2: Browse → Search → Detail → Action
**Narrative:** Find eligible student and assign housing

**Test Prompts:**
```
1. Show me all scholarship records (browse)
2. Check scholarship status for student S67890 (detail)
3. What vacant housing is available? (browse)
4. Get details for building-c-301 (detail)
5. Enroll student S67890 in building-c-301 (action)
```

**Policy Flow:**
- Steps 1-4: ✅ All allowed (read-only)
- Step 5: ✅ Allowed (write operation)

### Scenario 3: Emergency Response Workflow
**Narrative:** Severe weather requiring dam operations and rescue planning

**Test Prompts:**
```
1. What's the status of all dams? (list)
2. Check the southern dam specifically (detail)
3. Open southern dam floodgates due to storm (write - controlled)
4. What's the emergency status in the downstream area? (analysis)
5. Plan a rescue mission if needed (analysis)
```

**Policy Flow:**
- Steps 1-2: ✅ Allowed (read-only)
- Step 3: ✅ Allowed (requires auth in production)
- Steps 4-5: ✅ Allowed (emergency analysis)

---

## Testing Tips

1. **Start with Browse Operations:** Always test list_all tools first to see available data
2. **Chain Operations:** Test realistic workflows that combine browse → detail → action
3. **Test Policy Boundaries:** Try operations that should be blocked to verify security
4. **Verify Error Messages:** Blocked operations should return clear policy violation messages
5. **Check Tool Availability:** Use MCP's tools/list to verify all tools are registered

## Expected Tool Counts

- **Government MCP:** 14 tools total
  - 6 list/browse operations
  - 4 detail lookups
  - 2 emergency analysis
  - 1 write operation (floodgate_control)
  - 1 utility (ping)

- **Higher-Ed MCP:** 10 tools total
  - 4 list/browse operations
  - 3 detail lookups
  - 2 write operations (enroll_in_housing, unenroll_from_housing)
  - 1 utility (ping)

---

## Quick Reference: Policy Matrix

| Tool Category | Gov Policy | Higher-Ed Policy |
|--------------|------------|------------------|
| List/Browse (read-only) | ✅ Allow | ✅ Allow |
| Detail Lookup (read-only) | ✅ Allow | ✅ Allow |
| Emergency Analysis | ✅ Allow | N/A |
| Write Operations | ✅ Allow (with auth) | ⚠️ Mixed |
| Enroll Housing | N/A | ✅ Allow |
| Unenroll Housing | N/A | ❌ Deny |
| Floodgate Control | ✅ Allow (with auth) | N/A |
| Undefined Tools | ❌ Deny (default) | ❌ Deny (default) |

---

## Production Considerations

### Government Services
- **Floodgate Control:** Should verify JWT claims for infrastructure management role
- **Audit Logging:** All floodgate operations should be logged with user and reason
- **Rate Limiting:** Consider rate limits on emergency analysis tools

### Higher Education
- **Housing Enrollment:** Should verify student eligibility and housing availability
- **Housing Unenrollment:** Requires manual admin workflow (correctly blocked)
- **Data Privacy:** Consider masking sensitive student information in list operations
- **FERPA Compliance:** Ensure proper access controls for student records

---

## Troubleshooting

### HTTP 404 Not Found Error
**Symptom:** POST requests to MCP server return 404
```
HTTP Request: POST https://mcp-gov.triple-gate.traefik.ai "HTTP/1.1 404 Not Found"
```

**Root Cause:** The MCP gateway middleware was blocking protocol handshake requests (`initialize`, `tools/list`).

**Fix Applied:** Updated both MCP server policies to allow:
```yaml
- match: Equals(`mcp.method`, `initialize`)
  action: allow
- match: Equals(`mcp.method`, `tools/list`)
  action: allow
- match: Equals(`mcp.method`, `ping`)
  action: allow
```

**Resolution Steps:**
1. Ensure you have the latest policy configuration
2. Redeploy the MCP servers:
   ```bash
   helm upgrade --install gov ./gov/helm -n gov
   helm upgrade --install higher-ed ./higher-ed/helm -n higher-ed
   ```
3. Wait for pods to restart and become ready
4. Test again with any of the example prompts

### Tool Not Found
- Verify tool is registered in MCP server
- Check tool name spelling in policies
- Confirm MCP server is running and healthy
- Check server logs: `kubectl logs -n gov -l app=gov-mcp-server`

### Policy Denied
- Check if tool matches any policy rules
- Verify defaultAction setting
- Review policy match conditions (method and params.name)
- Ensure `initialize` and `tools/list` methods are allowed

### Connection Issues
- Verify Keycloak authentication is working
- Check JWT token is valid
- Confirm service endpoints are reachable
- Review CORS configuration if calling from browser
- Check IngressRoute is properly configured
- Verify DNS resolves to the correct Traefik instance

### Server Not Starting
**Check logs:**
```bash
kubectl logs -n gov -l app=gov-mcp-server
kubectl logs -n higher-ed -l app=higher-ed-mcp-server
```

**Common issues:**
- Python dependencies not installing (check requirements.txt)
- Port 8080 already in use
- Missing environment variables (KEYCLOAK_URL, service URLs)
- Syntax errors in mcp-server.yaml ConfigMap

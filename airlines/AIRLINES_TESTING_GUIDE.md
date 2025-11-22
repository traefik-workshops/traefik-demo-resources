# Airlines MCP Testing Guide

## 📊 Operational Dashboard

A real-time dashboard is available to monitor the state of the airline system.

**URL**: `https://ops.triple-gate.traefik.ai`

**Features**:
- **Live Flight Board**: Real-time status of all 20+ flights.
- **Booking Stats**: Total revenue and booking counts.
- **Passenger Count**: Active passengers and loyalty members.
- **Disruption Monitor**: Tracks delayed/cancelled flights.

Use this dashboard to visually verify the actions taken by the AI agent (e.g., seeing a new booking appear).

## 🧪 Test Scenarios
This guide provides comprehensive test scenarios for the Airlines demo showcasing Traefik's Triple Gateway Pattern.

## Prerequisites

```bash
# Deploy airlines services
helm upgrade --install airlines ./airlines/helm -n airlines --create-namespace

# Verify deployment
kubectl get pods -n airlines
kubectl get svc -n airlines

# Check MCP server logs
kubectl logs -n airlines -l component=ticketing-agent-mcp -f
kubectl logs -n airlines -l component=user-assistance-mcp -f
kubectl logs -n airlines -l component=partner-assistance-mcp -f
```

## MCP Protocol Requirements

The MCP gateway must allow:
1. **`initialize`** - Protocol handshake
2. **`tools/list`** - Discover available tools  
3. **`tools/call`** - Execute specific tools

## Table of Contents
- [Ticketing Agent MCP](#ticketing-agent-mcp)
- [User Assistance MCP](#user-assistance-mcp)
- [Partner Assistance MCP](#partner-assistance-mcp)
- [End-to-End Workflows](#end-to-end-workflows)

---

### 1. Ticketing Agent (B2C)

**Goal**: Verify the agent can search, book, and manage flights using the rich dataset.

#### Scenario 1.1: Complex Booking with Preferences
**Prompt**: 
> "Book a flight from New York (JFK) to London (LHR) for passenger P10001 (James Smith). He prefers a window seat and a vegetarian meal."

**Expected Behavior**:
1.  **Search**: Finds flights JFK -> LHR (e.g., FL105).
2.  **Profile**: Verifies James Smith exists.
3.  **Loyalty**: Checks tier (e.g., Gold) for discounts.
4.  **Booking**: Creates booking.
5.  **Seat**: Selects a window seat (e.g., 12A).
6.  **Meal**: Records 'vegetarian' preference via Ancillaries API.
7.  **Ticket**: Issues ticket.

**Verification**:
- Check Dashboard: "Recent Bookings" should show the new booking.
- Check API: `curl https://ancillaries.triple-gate.traefik.ai/ancillaries/meal` (if endpoint supports listing) or check logs.

#### Scenario 1.2: Loyalty Redemption
**Prompt**:
> "I want to use my miles to book a flight to Paris for passenger P10002."

## Ticketing Agent MCP

### 1. Flight Search and Booking

#### Test 1.1: Simple Flight Search
**Test Prompt:**
```
Find flights from New York JFK to Los Angeles LAX on March 15, 2024
```

**Expected Tool:** `search_flights`

**Expected Output:**
- ✅ Step-by-step trace of:
  1. Flight search API call
  2. Pricing calculation for each flight
  3. Seat availability check
- ✅ List of available flights with pricing
- ✅ Next step suggestion to book

**Example Response:**
```
✈️ **FLIGHT SEARCH INITIATED**
📍 Route: JFK → LAX
📅 Date: 2024-03-15
👥 Passengers: 1
💺 Class: economy

1️⃣ Searching available flights...
   ✅ Found 12 flights

2️⃣ Fetching pricing information...
   ✅ Flight FL123: $425.00
   ✅ Flight FL234: $450.00
   ✅ Flight FL345: $398.00
   ✅ Flight FL456: $475.00
   ✅ Flight FL567: $410.00

3️⃣ Checking seat availability...
   ✅ Flight FL123: 45 seats available
   ✅ Flight FL234: 32 seats available
   ...
```

#### Test 1.2: Complete Booking with Loyalty Benefits
**Test Prompt:**
```
Book flight FL123 for passenger P12345 with loyalty number FF987654. 
I prefer seat 12A and want to add checked baggage with a vegetarian meal.
```

**Expected Tool:** `book_flight_itinerary`

**Expected Output:**
- ✅ 10+ step trace showing:
  1. Flight details retrieval
  2. Passenger verification
  3. Loyalty status check with tier benefits
  4. Price calculation with discount
  5. Reservation creation
  6. Ticket issuance
  7. Seat selection (with fallback if unavailable)
  8. Baggage addition
  9. Meal preference recording
  10. Confirmation email sending
- ✅ Final booking reference
- ✅ Total price with discount breakdown
- ✅ Warning/error counts

**Policy:** ✅ Allowed

**Demonstrates:**
- Multi-API orchestration (flights, passengers, loyalty, pricing, bookings, tickets, checkin, baggage, ancillaries, notifications)
- Business logic (loyalty discounts, tier benefits)
- Error handling (seat not available → auto-assign)
- Comprehensive tracing

#### Test 1.3: Loyalty Status Check
**Test Prompt:**
```
What's my loyalty status for member number FF123456?
```

**Expected Tool:** `get_loyalty_status`

**Expected Output:**
- ✅ Member details (name, tier, miles)
- ✅ Progress to next tier
- ✅ Current tier benefits list
- ✅ Miles needed for next tier

**Policy:** ✅ Allowed

---

### 2. Booking Modifications

#### Test 2.1: Change Flight
**Test Prompt:**
```
I need to change booking BK789012 to flight FL567 instead. The original flight doesn't work with my schedule.
```

**Expected Tool:** `modify_booking`

**Expected Output:**
- Original booking details
- New flight details
- Change fee calculation
- Fare difference calculation  
- Refund or additional payment amount
- Rebooking confirmation
- Updated ticket issuance

**Policy:** ✅ Allowed

#### Test 2.2: Cancel with Refund
**Test Prompt:**
```
Cancel my booking BK789012 due to a family emergency
```

**Expected Tool:** `cancel_booking_with_refund`

**Expected Output:**
- Booking retrieval
- Fare rule lookup
- Refund eligibility check
- Cancellation fee calculation (if applicable)
- Loyalty status check (waive fees for high tiers)
- Refund processing
- Ticket voiding
- Confirmation email

**Policy:** ✅ Allowed

**Demonstrates:**
- Complex refund logic
- Loyalty benefit (fee waiver for Platinum/Diamond)
- Multiple API coordination

---

### 3. Check-in Operations

#### Test 3.1: Online Check-in
**Test Prompt:**
```
Check me in for booking BK456789 and I'd like seat 15F if possible
```

**Expected Tool:** `check_in_and_generate_boarding_pass`

**Expected Output:**
- Booking validation
- Check-in eligibility verification (24h before departure)
- Seat selection attempt
- Boarding pass generation with barcode
- Mobile boarding pass link

**Policy:** ✅ Allowed

---

### 4. Loyalty Operations

#### Test 4.1: Redeem Miles for Flight
**Test Prompt:**
```
Book flight FL999 for passenger P12345 using 25000 miles from loyalty account FF987654
```

**Expected Tool:** `redeem_miles_for_flight`

**Expected Output:**
- Miles availability check
- Flight pricing in miles
- Tier benefit application (reduced miles for higher tiers)
- Sufficient miles validation
- Award booking creation
- Miles deduction
- Ticket issuance

**Policy:** ✅ Allowed

**Demonstrates:**
- Award booking workflows
- Miles sufficiency validation
- Tier-based pricing

---

## User Assistance MCP

### 1. Disruption Management

#### Test 1.1: Handle Flight Cancellation
**Test Prompt:**
```
Flight FL123 was cancelled. Please help me rebook all affected passengers.
```

**Expected Tool:** `handle_flight_disruption`

**Expected Output:**
```
🚨 **FLIGHT DISRUPTION HANDLER**

1️⃣ Identifying affected passengers...
   ✅ Found 156 passengers on flight FL123

2️⃣ Finding alternative flights...
   ✅ Alternative FL124 (2h later): 120 seats available
   ✅ Alternative FL125 (4h later): 80 seats available
   
3️⃣ Checking passenger priorities...
   ✅ Diamond tier (12 passengers): Priority rebooking
   ✅ Platinum tier (23 passengers): Priority rebooking
   ✅ Gold tier (45 passengers): Standard rebooking
   ✅ Others (76 passengers): Standard rebooking

4️⃣ Calculating compensation eligibility...
   ✅ EU261 applies: €600 per passenger
   ✅ Meal vouchers: $15 per passenger

5️⃣ Processing automatic rebookings...
   ✅ Rebooked 145 passengers to FL124
   ✅ Rebooked 11 passengers to FL125
   ⚠️  Unable to rebook 0 passengers (manual intervention needed)

6️⃣ Issuing compensation...
   ✅ Travel vouchers issued to all passengers
   ✅ Meal vouchers distributed

7️⃣ Sending notifications...
   ✅ SMS sent to all passengers
   ✅ Email confirmations sent

**Summary**: Disruption handled successfully
**Total Passengers**: 156
**Successfully Rebooked**: 156 (100%)
**Compensation Issued**: €93,600
**Notifications Sent**: 312 (SMS + Email)
```

**Policy:** ✅ Allowed

**Demonstrates:**
- Bulk passenger operations
- Priority handling by loyalty tier
- Automated compensation calculation
- Mass rebooking orchestration
- Multi-channel notifications

#### Test 1.2: Handle Delay Compensation
**Test Prompt:**
```
Flight FL789 is delayed by 5 hours. What compensation do passengers get?
```

**Expected Tool:** `calculate_delay_compensation`

**Expected Output:**
- Delay duration verification
- Compensation regulation check (EU261, DOT, etc.)
- Per-passenger entitlement calculation
- Voucher/refund processing
- Notification to passengers

**Policy:** ✅ Allowed

---

### 2. Customer Issues

#### Test 2.1: Lost Baggage Claim
**Test Prompt:**
```
Passenger P12345 reports lost baggage from flight FL456, bag tag BT789012
```

**Expected Tool:** `process_baggage_claim`

**Expected Output:**
- Bag tag validation
- Baggage tracking query
- Last known location
- Interim compensation (toiletries allowance)
- Delivery arrangements if found
- Claim filing if not found

**Policy:** ✅ Allowed

#### Test 2.2: Special Assistance Request
**Test Prompt:**
```
Passenger P67890 on booking BK111222 needs wheelchair assistance and has a severe peanut allergy
```

**Expected Tool:** `arrange_special_assistance`

**Expected Output:**
- Booking retrieval
- Special Service Request (SSR) codes application
- Wheelchair coordination at departure and arrival airports
- Meal modification (remove peanuts)
- Crew notification
- Gate notification
- Confirmation to passenger

**Policy:** ✅ Allowed

**Demonstrates:**
- Accessibility compliance
- Medical requirement handling
- Cross-department coordination

---

### 3. Upgrade Processing

#### Test 3.1: Process Upgrade Request
**Test Prompt:**
```
Can passenger P12345 on booking BK333444 be upgraded to business class using miles?
```

**Expected Tool:** `process_upgrade_request`

**Expected Output:**
- Availability check in higher cabin
- Miles required calculation
- Tier-based miles discount
- Upgrade confirmation or waitlist
- New boarding pass issuance

**Policy:** ✅ Allowed

---

## Partner Assistance MCP

### 1. Partner Flight Operations

#### Test 1.1: Enroll New Partner Flight
**Test Prompt:**
```
Enroll a new flight from partner airline PA123: 
Flight PA9876 from SFO to NRT, operates daily, 
equipment B777-300ER, codeshare with our FL5000
```

**Expected Tool:** `enroll_partner_flight`

**Expected Output:**
```
🤝 **PARTNER FLIGHT ENROLLMENT**

1️⃣ Validating partner credentials...
   ✅ Partner Airline: Pacific Airways (PA123)
   ✅ Agreement Status: Active
   ✅ Codeshare Rights: Verified

2️⃣ Checking route authority...
   ✅ Route SFO-NRT: Authorized
   ✅ Slot availability: Confirmed

3️⃣ Creating flight schedule...
   ✅ Flight PA9876 created
   ✅ Operating days: Daily
   ✅ Aircraft type: B777-300ER registered

4️⃣ Configuring codeshare...
   ✅ Our flight number: FL5000
   ✅ Revenue share: 40% (per agreement)
   ✅ Inventory link established

5️⃣ Updating GDS systems...
   ✅ Published to Amadeus
   ✅ Published to Sabre
   ✅ Published to Travelport

6️⃣ Setting pricing rules...
   ✅ Base fare configured
   ✅ Dynamic pricing enabled
   ✅ Partner commission: 7%

7️⃣ Initializing inventory...
   ✅ Economy: 280 seats
   ✅ Business: 52 seats
   ✅ First: 8 seats

**Summary**: Partner flight enrolled successfully
**Codeshare Flight**: FL5000
**Effective Date**: 2024-04-01
**GDS Distribution**: ✅ Complete
```

**Policy:** ✅ Allowed (requires partner admin role)

**Demonstrates:**
- Complex authorization checks
- Multi-system integration
- Revenue sharing configuration
- GDS distribution

#### Test 1.2: Update Partner Schedule
**Test Prompt:**
```
Partner flight PA9876 needs to change departure time from 15:00 to 16:30 starting April 15
```

**Expected Tool:** `update_partner_schedule`

**Expected Output:**
- Schedule change validation
- Affected booking identification
- Passenger notification
- GDS update
- Partner notification

**Policy:** ✅ Allowed

---

### 2. Alliance Operations

#### Test 2.1: Process Alliance Booking
**Test Prompt:**
```
Book a multi-carrier itinerary: our FL100 (JFK-LHR) connecting to 
partner PA500 (LHR-DXB) for passenger P99999
```

**Expected Tool:** `create_alliance_booking`

**Expected Output:**
- Multi-carrier itinerary validation
- Connection time verification
- Through check-in eligibility
- Baggage through-tagging setup
- Coordinated ticket issuance
- Both carriers' systems update

**Policy:** ✅ Allowed

---

### 3. Revenue Management

#### Test 3.1: Partner Revenue Reconciliation
**Test Prompt:**
```
Generate revenue reconciliation report for partner PA123 for March 2024
```

**Expected Tool:** `reconcile_partner_revenue`

**Expected Output:**
- Total bookings by flight
- Revenue by segment
- Commission calculations
- Interline settlement amounts
- Discrepancy identification
- Settlement file generation

**Policy:** ✅ Allowed (requires finance role)

---

## End-to-End Workflows

### Workflow 1: Complete Travel Journey

**Scenario:** Business traveler books, modifies, checks in, and travels

**Test Prompts (sequential):**
```
1. Search flights from San Francisco to Tokyo for May 1, 2024, business class

2. Book flight FL9000 for passenger P11111, loyalty number FF555666, 
   prefer seat 2A, add 2 checked bags, kosher meal

3. What's my loyalty status for member FF555666?

4. Actually, I need to change my flight to May 2 instead (booking BK[from step 2])

5. Check me in for my flight and get boarding pass

6. I'm at the airport but my bag hasn't arrived (bag tag from check-in)
```

**Demonstrates:**
- Complete customer journey
- Multi-MCP server coordination
- Context retention
- Error recovery

---

### Workflow 2: Irregular Operations

**Scenario:** Weather causes mass delays and cancellations

**Test Prompts (sequential):**
```
1. Flight FL200 is cancelled due to weather. Handle all passenger rebookings.

2. Calculate compensation for passengers on delayed flight FL201 (6 hour delay)

3. Passenger P22222 missed their connection on FL202 due to the FL200 cancellation. 
   Help them get to their final destination.
```

**Demonstrates:**
- Crisis management
- Automated recovery
- Priority handling  
- Compensation automation

---

### Workflow 3: Partner Integration

**Scenario:** New airline joins alliance

**Test Prompts (sequential):**
```
1. Enroll partner airline PA999 with 3 daily flights from LAX to SYD

2. Create alliance booking: our FL300 (JFK-LAX) connecting to PA999 (LAX-SYD)

3. Process upgrade for passenger on the alliance itinerary using miles
```

**Demonstrates:**
- Partner onboarding
- Multi-carrier operations
- Alliance benefits

---

## Policy Testing

### Test: MCP Method Authorization

**Prompts:**
```
1. Initialize connection (should succeed)
2. List available tools (should succeed)
3. Call any tool (should be policy-controlled)
```

**Expected Policy Flow:**
- ✅ `initialize` - Always allowed
- ✅ `tools/list` - Always allowed  
- ⚠️ `tools/call` - Depends on specific tool and user role

### Test: Role-Based Access

**Ticketing Agent Tools:**
- ✅ Customer can: search, book, modify, check-in
- ❌ Customer cannot: enroll partner flights, reconcile revenue

**User Assistance Tools:**
- ✅ Support agent can: handle disruptions, process claims, arrange assistance
- ❌ Support agent cannot: create bookings, enroll partners

**Partner Assistance Tools:**
- ✅ Partner admin can: enroll flights, update schedules, view revenue
- ❌ Partner admin cannot: access customer PII, modify other partners

---

## Expected Tool Counts

- **Ticketing Agent MCP:** 8 tools
  - search_flights
  - book_flight_itinerary
  - modify_booking
  - cancel_booking_with_refund
  - check_in_and_generate_boarding_pass
  - get_loyalty_status
  - redeem_miles_for_flight
  - ping

- **User Assistance MCP:** 10 tools
  - handle_flight_disruption
  - calculate_delay_compensation
  - process_baggage_claim
  - arrange_special_assistance
  - process_upgrade_request
  - issue_travel_voucher
  - handle_customer_complaint
  - process_refund_request
  - track_flight_status
  - ping

- **Partner Assistance MCP:** 8 tools
  - enroll_partner_flight
  - update_partner_schedule
  - create_alliance_booking
  - reconcile_partner_revenue
  - manage_codeshare_agreement
  - configure_revenue_sharing
  - sync_partner_inventory
  - ping

---

## Troubleshooting

### MCP Server Not Responding
```bash
# Check pod status
kubectl get pods -n airlines -l component=mcp

# View logs
kubectl logs -n airlines -l component=ticketing-agent-mcp --tail=100

# Common issues:
# - Python dependencies not installed
# - Keycloak authentication failing
# - Backend API services not ready
```

### API Calls Failing
```bash
# Verify backend services
kubectl get svc -n airlines

# Test service connectivity
kubectl run -n airlines test-pod --image=curlimages/curl -it --rm -- \
  curl http://flights-app.airlines.svc.cluster.local:3000/flights
```

### Policy Blocking Requests
```bash
# Check MCP gateway policy
kubectl get middleware -n airlines

# View gateway logs
kubectl logs -n traefik deployment/traefik -f | grep mcp
```

---

## Success Metrics

A successful test should show:
- ✅ All process steps logged
- ✅ API calls traced with results
- ✅ Errors gracefully handled with fallbacks
- ✅ Clear success/warning/error counts
- ✅ Actionable next steps provided
- ✅ Booking references and confirmation details
- ✅  Response time < 5 seconds for most operations

# Hoppscotch Collection Refactoring Analysis

## Summary

| Metric | Before | After |
|--------|--------|-------|
| Total Requests | 85 | 95 |
| Standalone Token Fetches | 24 | 0 |
| Actual API Tests | 61 | 95 |
| Tests with Pre-processing | 1 | 95 |
| Tests with Validation | 85 | 95 |
| 3-Phase Complete (pre+test) | 1 | 95 |

## Key Changes

### 1. Token Management
- **Before:** 24 standalone token fetch requests scattered as the first request in each folder
- **After:** 0 standalone token requests. Every request handles its own auth via `preRequestScript`
- **Impact:** Tests are now independent — each can run in isolation without ordering dependencies

### 2. Airlines APIs — Admin-Only Auth
- **Before:** Mixed auth (dispatcher for flight-ops, agent for passenger-svc, handler for airport-ops)
- **After:** All Airlines API tests use `admin` credentials (full CRUD access across all APIs)
- **Rationale:** Airlines APIs section validates OpenAPI spec coverage, not access control

### 3. Three-Phase Test Pattern
- **Phase 1 — Pre-processing:** Token acquisition + resource setup in `preRequestScript`
- **Phase 2 — Execution:** The actual HTTP request (method, endpoint, body)
- **Phase 3 — Validation:** Response assertions in `testScript`
- **Before:** Only 1 of 85 requests had a pre-processing script
- **After:** All 95 requests follow the full 3-phase pattern

### 4. OpenAPI Spec Coverage
- **Before:** Missing PUT, PATCH, search endpoints for most services
- **After:** Full CRUD + search + custom endpoints for all 9 services

### 5. Traefik Demo — Operation Sets (renamed from Access Control)
- **Before:** 3 tests (dispatcher reads flights, dispatcher blocked on gates)
- **After:** 9 tests covering read/write/delete operation filtering for dispatcher, agent, handler, and admin
- Demonstrates Traefik Hub's operation-set-based access control per user role

## Detailed Per-Section Analysis

### Traefik Airlines/Airlines APIs/Airport Operations/Baggage

| | Before | After |
|--|--------|-------|
| Requests | 7 | 9 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 9 |
| With testScript | 7 | 9 |

**Tests:**

- `GET` **List All Baggage** — Phases: pre-processing → execution → validation
- `GET` **Search Baggage** — Phases: pre-processing → execution → validation
- `POST` **Check In Bag** — Phases: pre-processing → execution → validation
- `GET` **Track Bag** — Phases: pre-processing → execution → validation
- `GET` **Get Baggage by Booking** — Phases: pre-processing → execution → validation
- `PUT` **Update Baggage (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Baggage (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Remove Baggage Record** — Phases: pre-processing → execution → validation
- `GET` **Track Bag v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Airport Operations/Check-in

| | Before | After |
|--|--------|-------|
| Requests | 6 | 9 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 9 |
| With testScript | 6 | 9 |

**Tests:**

- `GET` **List All Check-ins** — Phases: pre-processing → execution → validation
- `GET` **Search Check-ins** — Phases: pre-processing → execution → validation
- `POST` **Process Check-in** — Phases: pre-processing → execution → validation
- `GET` **Get Check-in Record** — Phases: pre-processing → execution → validation
- `GET` **Get Boarding Pass** — Phases: pre-processing → execution → validation
- `PUT` **Update Check-in (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Check-in (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Check-in Record** — Phases: pre-processing → execution → validation
- `GET` **Get Check-in v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Airport Operations/Gates

| | Before | After |
|--|--------|-------|
| Requests | 6 | 7 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 7 |
| With testScript | 6 | 7 |

**Tests:**

- `GET` **List All Gates** — Phases: pre-processing → execution → validation
- `GET` **Search Gates** — Phases: pre-processing → execution → validation
- `POST` **Assign Gate** — Phases: pre-processing → execution → validation
- `GET` **Get Gate** — Phases: pre-processing → execution → validation
- `PUT` **Update Gate (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Gate (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Release Gate** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Flight Operations/Crew

| | Before | After |
|--|--------|-------|
| Requests | 6 | 7 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 7 |
| With testScript | 6 | 7 |

**Tests:**

- `GET` **List All Crew** — Phases: pre-processing → execution → validation
- `GET` **Search Crew** — Phases: pre-processing → execution → validation
- `POST` **Assign Crew Member** — Phases: pre-processing → execution → validation
- `GET` **Get Crew Member** — Phases: pre-processing → execution → validation
- `PUT` **Update Crew Member (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Crew (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Crew Member** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Flight Operations/Flights

| | Before | After |
|--|--------|-------|
| Requests | 9 | 8 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 8 |
| With testScript | 9 | 8 |

**Tests:**

- `GET` **List All Flights** — Phases: pre-processing → execution → validation
- `GET` **Search Flights** — Phases: pre-processing → execution → validation
- `POST` **Create Flight** — Phases: pre-processing → execution → validation
- `GET` **Get Flight by ID** — Phases: pre-processing → execution → validation
- `PUT` **Update Flight (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Flight (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Flight** — Phases: pre-processing → execution → validation
- `GET` **List Flights v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Flight Operations/Pricing

| | Before | After |
|--|--------|-------|
| Requests | 7 | 8 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 8 |
| With testScript | 7 | 8 |

**Tests:**

- `GET` **List All Pricing** — Phases: pre-processing → execution → validation
- `GET` **Search Pricing** — Phases: pre-processing → execution → validation
- `POST` **Calculate Fare** — Phases: pre-processing → execution → validation
- `GET` **Get Fare Rule** — Phases: pre-processing → execution → validation
- `PUT` **Update Fare Rule (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Fare (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Fare Rule** — Phases: pre-processing → execution → validation
- `GET` **Get Pricing v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Passenger Services/Bookings

| | Before | After |
|--|--------|-------|
| Requests | 7 | 8 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 8 |
| With testScript | 7 | 8 |

**Tests:**

- `GET` **List All Bookings** — Phases: pre-processing → execution → validation
- `GET` **Search Bookings** — Phases: pre-processing → execution → validation
- `POST` **Create Booking** — Phases: pre-processing → execution → validation
- `GET` **Get Booking** — Phases: pre-processing → execution → validation
- `PUT` **Update Booking (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Booking (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Cancel Booking (DELETE)** — Phases: pre-processing → execution → validation
- `GET` **List Bookings v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Passenger Services/Notifications

| | Before | After |
|--|--------|-------|
| Requests | 6 | 8 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 8 |
| With testScript | 6 | 8 |

**Tests:**

- `GET` **List All Notifications** — Phases: pre-processing → execution → validation
- `GET` **Search Notifications** — Phases: pre-processing → execution → validation
- `POST` **Send Notification** — Phases: pre-processing → execution → validation
- `GET` **Get Notification** — Phases: pre-processing → execution → validation
- `GET` **Get Notification History** — Phases: pre-processing → execution → validation
- `PUT` **Update Notification (PUT)** — Phases: pre-processing → execution → validation
- `PATCH` **Partial Update Notification (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Notification** — Phases: pre-processing → execution → validation

### Traefik Airlines/Airlines APIs/Passenger Services/Passengers

| | Before | After |
|--|--------|-------|
| Requests | 8 | 7 |
| Token-only | 2 | 0 |
| With preRequestScript | 0 | 7 |
| With testScript | 8 | 7 |

**Tests:**

- `GET` **List All Passengers** — Phases: pre-processing → execution → validation
- `GET` **Search Passengers** — Phases: pre-processing → execution → validation
- `POST` **Create Passenger** — Phases: pre-processing → execution → validation
- `GET` **Get Passenger** — Phases: pre-processing → execution → validation
- `PATCH` **Update Passenger (PATCH)** — Phases: pre-processing → execution → validation
- `DELETE` **Delete Passenger** — Phases: pre-processing → execution → validation
- `GET` **Get Passengers v1 (Deprecated — check headers)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Gateway/Request Transformation

| | Before | After |
|--|--------|-------|
| Requests | 2 | 1 |
| Token-only | 1 | 0 |
| With preRequestScript | 0 | 1 |
| With testScript | 2 | 1 |

**Tests:**

- `GET` **List Flights — Observe Injected Headers** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Gateway/WAF

| | Before | After |
|--|--------|-------|
| Requests | 4 | 3 |
| Token-only | 1 | 0 |
| With preRequestScript | 0 | 3 |
| With testScript | 4 | 3 |

**Tests:**

- `GET` **List Bookings — Clean Request (200)** — Phases: pre-processing → execution → validation
- `GET` **SQL Injection Attack (Expect 403)** — Phases: pre-processing → execution → validation
- `GET` **XSS Attack (Expect 403)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Management/Operation Sets (was: Access Control)

| | Before | After |
|--|--------|-------|
| Requests | 3 | 0 |
| Token-only | 1 | 0 |
| With preRequestScript | 0 | 0 |
| With testScript | 3 | 0 |

### Traefik Airlines/Traefik Demo/API Management/Method & Path Validation

| | Before | After |
|--|--------|-------|
| Requests | 4 | 3 |
| Token-only | 1 | 0 |
| With preRequestScript | 0 | 3 |
| With testScript | 4 | 3 |

**Tests:**

- `GET` **Valid Method + Path (200)** — Phases: pre-processing → execution → validation
- `DELETE` **Invalid Method on Valid Path (404)** — Phases: pre-processing → execution → validation
- `GET` **Path Not in Spec (404)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Management/Operation Sets

| | Before | After |
|--|--------|-------|
| Requests | 0 | 9 |
| Token-only | 0 | 0 |
| With preRequestScript | 0 | 9 |
| With testScript | 0 | 9 |

**Tests:**

- `GET` **Dispatcher: Read Flights (200)** — Phases: pre-processing → execution → validation
- `POST` **Dispatcher: Create Flight (201)** — Phases: pre-processing → execution → validation
- `DELETE` **Dispatcher: Delete Flight (403 — no delete-flights)** — Phases: pre-processing → execution → validation
- `GET` **Dispatcher: Access Gates API (403 — wrong bundle)** — Phases: pre-processing → execution → validation
- `GET` **Agent: Read Bookings (200)** — Phases: pre-processing → execution → validation
- `DELETE` **Agent: Delete Booking (403 — no delete-bookings)** — Phases: pre-processing → execution → validation
- `GET` **Handler: Read Gates (200)** — Phases: pre-processing → execution → validation
- `GET` **Handler: Access Flights API (403 — wrong bundle)** — Phases: pre-processing → execution → validation
- `DELETE` **Admin: Delete Flight (200 — has delete-flights)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Management/Plans & Quotas

| | Before | After |
|--|--------|-------|
| Requests | 2 | 1 |
| Token-only | 1 | 0 |
| With preRequestScript | 1 | 1 |
| With testScript | 2 | 1 |

**Tests:**

- `GET` **Analyst: Quota Exhausted (Expect 429)** — Phases: pre-processing → execution → validation

### Traefik Airlines/Traefik Demo/API Management/Request Body Validation

| | Before | After |
|--|--------|-------|
| Requests | 8 | 7 |
| Token-only | 1 | 0 |
| With preRequestScript | 0 | 7 |
| With testScript | 8 | 7 |

**Tests:**

- `POST` **Valid Flight Creation (201)** — Phases: pre-processing → execution → validation
- `POST` **Valid Booking Creation (201)** — Phases: pre-processing → execution → validation
- `POST` **Missing Required Field (400)** — Phases: pre-processing → execution → validation
- `POST` **Wrong Field Type (400)** — Phases: pre-processing → execution → validation
- `POST` **Invalid Enum Value (400)** — Phases: pre-processing → execution → validation
- `POST` **Empty Body (400)** — Phases: pre-processing → execution → validation
- `POST` **Null Required Field (400)** — Phases: pre-processing → execution → validation

## Next Steps

1. Deploy the updated chart to the transit cluster: `helm upgrade airlines ./helm`
2. Run the test suite: `./test-collection.sh demo.traefik.ai`
3. Verify all 95 tests pass against the live deployment
4. Iterate on any failures (some services may return different status codes than expected)

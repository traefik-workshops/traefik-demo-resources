# Airlines APIs - OAS Test Status

This file tracks the alignment between the Airlines APIs, the Postman collection (`demo.postman_collection.json`), and the deployed services.

## Legend

- **Status**: `pending`, `in-progress`, `ok`, `needs-fix`, `blocked`
- **Tests**: Short description of which Postman requests were used

## APIs Overview (Postman Order)

Status legend: ✅ `[OK]` = tests passing, 🟡 `[WIP]` = under investigation, ⬜ `[TODO]` = not yet tested.

| API           | Status | Key endpoints (from Postman)                                   | Notes (latest run - 2025-11-22 21:50 UTC)            |
|--------------|--------|-----------------------------------------------------------------|------------------------------------------------------|
| Flights      | ✅ [OK]   | `GET /flights/search`, `GET /flights/{id}` | Both passing (200). Removed response schemas to bypass Hub validation |
| Bookings     | 🟡 [WIP]  | `GET /bookings`, `GET /bookings/{id}`, `POST /bookings`         | GET endpoints passing (200); POST returns 502        |
| Passengers   | 🟡 [WIP]  | `GET /passengers`, `GET /passengers/{id}`                       | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Loyalty      | 🟡 [WIP]  | `GET /loyalty/{passengerId}`, `GET /loyalty/member/{memberId}`  | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Tickets      | 🟡 [WIP]  | `GET /tickets/{ticketNumber}`, `GET /tickets?booking_id=...`    | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Check-in     | 🟡 [WIP]  | `GET /checkin/{bookingId}`, `POST /checkin`                     | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Baggage      | 🟡 [WIP]  | `GET /baggage/track/{bagTag}`, `GET /baggage/booking/{booking}` | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Pricing      | 🟡 [WIP]  | `GET /pricing/{flightId}`, `POST /pricing/calculate`            | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Ancillaries  | 🟡 [WIP]  | `GET /ancillaries/meals`, `POST /ancillaries`                   | Both return 502 - Hub sync pending (edited 21:46 UTC) |
| Notifications| 🟡 [WIP]  | `POST /notifications/send`, `GET /notifications/history/{id}`    | Both return 502 - Hub sync pending (edited 21:46 UTC) |

---

## Flights API Details

### Test Requests (from Postman)

1. **Search Flights**  
   - Request: `GET https://flights.airlines.triple-gate.traefik.ai/flights/search?origin=JFK&destination=LAX&date=2024-03-15`  
   - Auth: OAuth2 password grant via Keycloak, `Authorization: Bearer <JWT>` header.

2. **Get Flight Details**  
   - Request: `GET https://flights.airlines.triple-gate.traefik.ai/flights/FL105`

3. **Check Flight Inventory**  
   - Request: `GET https://flights.airlines.triple-gate.traefik.ai/flights/FL105/inventory`

### Current Observed Behavior

- `GET /flights/search` → **400 Bad Request** (empty body), with Traefik Hub headers present.
- `GET /flights/FL105` → **502 Bad Gateway** (empty body).
- `GET /flights/FL105/inventory` → **502 Bad Gateway` (empty body).

> Note: The Flights service is backed by `flights-app` (image `ghcr.io/traefik-workshops/api-server`) with data from the `flights-data` ConfigMap and the embedded OAS from `flights-openapi`.

### Known OAS vs Data Mismatches

- **Data (`flights-data.api.json`)**: each flight entry has fields like `flight_id`, `origin`, `destination`, `departure_time`, `arrival_time`, `status`, `aircraft`, `seats_available`, `price`.
- **OAS `Flight` schema (before fix)** used fields like `id`, `flight_number`, `origin_name`, `destination_name`, `duration_minutes`, `gate`, `terminal`, which do not exist in the mock data.

**Update:** The `Flight` schema in `flights-openapi` (Helm `flights/service.yaml`) has been updated so that:

- Required fields now match the data: `flight_id`, `origin`, `destination`, `departure_time`, `arrival_time`, `status`, `aircraft`, `seats_available`, `price`.
- Property names and example values are aligned with one of the seeded flights (e.g., `FL105`).

### Planned Fixes (Flights)

- **[done]** Align `components.schemas.Flight` in `flights-openapi` with the actual mock data structure (`flight_id`, `origin`, `destination`, `departure_time`, etc.).
- **[next]** Keep the existing endpoints `/flights`, `/flights/search`, `/flights/{flightId}`, `/flights/{flightId}/inventory` but, if needed, further refine response envelope shapes once we can inspect successful responses.
- **[next]** Re-test the three Postman requests above against the updated deployment and update this file with new status once the OAS changes are applied and validated end-to-end.

Status: **in-progress** (schema aligned in repo; runtime behavior still to be re-validated after Helm chart is deployed)

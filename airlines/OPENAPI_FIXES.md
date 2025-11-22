# Airlines API OpenAPI Spec Fixes Required

## Summary
The Postman collection uses simple REST patterns, but the OpenAPI specs have more complex endpoints.
We need to update the OpenAPI specs to match the Postman collection examples.

## Required Fixes

### 1. Flights API ✅
- Fixed: Changed `dest` parameter to `destination` in `/flights/search`
- Endpoints match Postman collection

### 2. Bookings API
**Postman expects:**
- GET `/bookings` - List all bookings
- GET `/bookings/{bookingId}` - Get booking details  
- POST `/bookings` - Create booking with body: `{flight_id, passenger_id, class}`

**Current OpenAPI has:**
- GET `/bookings` ✅
- GET `/bookings/{bookingId}` ✅
- Needs POST `/bookings` endpoint added

### 3. Passengers API
**Postman expects:**
- GET `/passengers` - List all passengers
- GET `/passengers/{passengerId}` - Get passenger profile

**Current OpenAPI has:**
- GET `/passengers` ✅
- GET `/passengers/{passengerId}` ✅
- Should be OK

### 4. Loyalty API  
**Postman expects:**
- GET `/loyalty/{passengerId}` - Get loyalty status by passenger ID
- GET `/loyalty/member/{loyaltyNumber}` - Get member details by loyalty number

**Current OpenAPI has:**
- GET `/loyalty/members/{loyaltyNumber}` - Wrong path!
- Needs both endpoints added/fixed

### 5. Tickets API
**Postman expects:**
- GET `/tickets/{ticketId}` - Get ticket details
- GET `/tickets?booking_id={bookingId}` - List tickets for booking

**Current OpenAPI has:**
- GET `/tickets/{ticketNumber}` - Close but parameter name might be wrong
- POST `/tickets/issue`
- POST `/tickets/void`
- Needs query parameter support for booking_id

### 6. Check-in API
**Postman expects:**
- GET `/checkin/{bookingId}` - Get check-in status
- POST `/checkin` - Perform check-in with body: `{booking_id, seat}`

**Current OpenAPI has:**
- GET `/checkin/{bookingId}/seat`
- POST `/checkin/{bookingId}/seat`
- POST `/checkin/{bookingId}/seat/auto`
- GET `/checkin/{bookingId}/boarding-pass`
- Needs simpler endpoints

### 7. Baggage API
**Postman expects:**
- GET `/baggage/track/{bagTag}` - Track baggage
- GET `/baggage/booking/{bookingId}` - Get baggage for booking

**Current OpenAPI has:**
- POST `/baggage/add`
- GET `/baggage/track/{bagTag}` ✅
- Needs `/baggage/booking/{bookingId}` endpoint

### 8. Pricing API
**Postman expects:**
- GET `/pricing/{flightId}?class={class}&passengers={count}` - Get flight pricing
- POST `/pricing/calculate` - Calculate total price with body: `{flight_id, class, passengers}`

**Current OpenAPI has:**
- POST `/pricing/calculate` ✅
- Needs GET `/pricing/{flightId}` endpoint

### 9. Ancillaries API
**Postman expects:**
- GET `/ancillaries/meals` - Get meal options
- POST `/ancillaries` - Add ancillary with body: `{booking_id, type, preference}`

**Current OpenAPI has:**
- POST `/ancillaries/meal`
- POST `/ancillaries/seat-upgrade`
- Needs GET `/ancillaries/meals` and POST `/ancillaries` endpoints

### 10. Notifications API
**Postman expects:**
- POST `/notifications/send` - Send notification with body: `{type, recipient, booking_id}`
- GET `/notifications/history/{passengerId}` - Get notification history

**Current OpenAPI has:**
- POST `/notifications/send` ✅
- Needs GET `/notifications/history/{passengerId}` endpoint

## Action Plan
1. Update each service's OpenAPI spec in their respective service.yaml files
2. Add missing endpoints
3. Fix parameter names and paths
4. Ensure request/response schemas match Postman examples
5. Test with Postman collection

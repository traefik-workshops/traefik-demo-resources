# Stateful In-Memory Services for Airlines

## Overview

This directory contains Python-based microservices that provide **stateful, in-memory storage** for all airline data. Unlike the previous read-only mock services, these support full CRUD operations.

## Architecture

- **Base Service** (`base_service.py`): Generic Flask-based REST API with in-memory storage
- **Service Entry Points**: Specialized services for each resource type
- **In-Memory Store**: Python dict-based storage (data persists during pod lifetime, resets on restart)

## Features

✅ **Full CRUD Support**:
- `GET /{resource}` - List all records
- `GET /{resource}/<id>` - Get single record
- `POST /{resource}` - Create new record
- `PUT/PATCH /{resource}/<id>` - Update record
- `DELETE /{resource}/<id>` - Delete record
- `GET /{resource}/search?key=value` - Search/filter records

✅ **Automatic ID Generation**: UUIDs generated for new records without IDs

✅ **Initial Data Loading**: Seeds from ConfigMap at startup

✅ **Query Parameter Filtering**: Support for search parameters

## Services

| Service | Resource Path | ID Field | Entry Point |
|---------|---------------|----------|-------------|
| Flights | `/flights` | `flight_id` | `flights_service.py` |
| Bookings | `/bookings` | `booking_id` | `bookings_service.py` |
| Check-in | `/checkin` | `booking_id` | `checkin_service.py` |
| Loyalty | `/loyalty` | `member_id` | `loyalty_service.py` |

## Building the Image

```bash
cd /Users/zaidalbirawi/dev/traefik-resources/airlines/services

# Build the image
docker build -t ghcr.io/traefik-workshops/airlines-stateful-api:v0.1.0 .

# Push to registry (if needed)
docker push ghcr.io/traefik-workshops/airlines-stateful-api:v0.1.0
```

## Usage in Kubernetes

### Update Helm Deployment

Modify each service's deployment to use the new image and specify the service:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flights-app
spec:
  template:
    spec:
      containers:
        - name: api
          image: ghcr.io/traefik-workshops/airlines-stateful-api:v0.1.0
          command: ["python", "flights_service.py"]  # Specify which service
          volumeMounts:
            - name: api-data
              mountPath: /api
            - name: openapi
              mountPath: /public
```

### Or use environment variables:

```yaml
containers:
  - name: api
    image: ghcr.io/traefik-workshops/airlines-stateful-api:v0.1.0
    env:
      - name: SERVICE_NAME
        value: "Flights"
      - name: RESOURCE_PATH
        value: "flights"
      - name: ID_FIELD
        value: "flight_id"
```

## Example Operations

### Search Flights
```bash
GET /flights/search?origin=JFK&destination=LAX
```

### Book Flight (Create Booking)
```bash
POST /bookings
{
  "flight_id": "FL123",
  "passenger_id": "P001",
  "total_price": 450.00,
  "status": "confirmed"
}
```

### Modify Booking
```bash
PUT /bookings/BK12345
{
  "flight_id": "FL124",
  "change_fee": 75.00
}
```

### Cancel Booking
```bash
DELETE /bookings/BK12345
```

### Check-in
```bash
POST /checkin/BK12345
{
  "seat": "12A",
  "checked_in": true,
  "boarding_pass": "BP12345A"
}
```

## MCP Integration

Once deployed, all MCP tools will work with live data:

1. **Search Flights** → Returns current in-memory flight data
2. **Book Flight** → Creates new booking record in memory
3. **Modify Booking** → Updates existing booking
4. **Cancel Booking** → Deletes booking from memory
5. **Check-in** → Creates check-in record
6. **Redeem Miles** → Updates loyalty balance

All changes are **immediately visible** in subsequent API calls and in the dashboard!

## Data Persistence

### During Pod Lifetime
- ✅ Data persists in memory
- ✅ Multiple requests see the same state
- ✅ Changes accumulate

### On Pod Restart
- ❌ All changes are lost
- ✅ Data reloads from initial ConfigMap
- ⚠️ This is acceptable for demo purposes

### For Production
To persist data across restarts, consider:
- Redis backend
- PostgreSQL/MySQL
- Persistent Volume with SQLite

## Next Steps

1. **Build and push the Docker image**
2. **Update Helm values.yaml** to use new image:
   ```yaml
   image:
     repository: ghcr.io/traefik-workshops/airlines-stateful-api
     tag: v0.1.0
   ```
3. **Update each service deployment** to specify the correct entry point
4. **Deploy with `terraform apply`** or `helm upgrade`
5. **Test MCP operations** to see live data changes

## Monitoring

Each service exposes:
- `GET /health` - Health check with record count
- Logs show all CREATE/UPDATE/DELETE operations

```bash
# View logs
kubectl logs -n airlines flights-app-xxxxx

# Check health
curl http://flights.airlines.svc.cluster.local:3000/health
```

## Troubleshooting

### Service won't start
- Check logs: `kubectl logs -n airlines <pod-name>`
- Verify ConfigMap is mounted at `/api/api.json`
- Ensure correct Python dependencies

### Data not loading
- Verify ConfigMap format matches expected structure
- Check logs for "Loaded X records"
- Ensure JSON is valid

### Changes not persisting
- Remember: data only persists during pod lifetime
- Pod restart = data reset to initial state
- This is by design for demo environment

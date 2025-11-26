# Airlines Stateful Services

In-memory database microservices for the Airlines project.

## Architecture

**ONE Docker image for ALL 10 services**

```
airlines-stateful-api:v0.1.0
├── base_service.py          (Core in-memory CRUD)
├── flights_service.py       (Flights endpoint)
├── bookings_service.py      (Bookings endpoint)
├── checkin_service.py       (Check-in endpoint)
├── loyalty_service.py       (Loyalty endpoint)
├── tickets_service.py       (Tickets endpoint)
├── passengers_service.py    (Passengers endpoint)
├── pricing_service.py       (Pricing endpoint)
├── baggage_service.py       (Baggage endpoint)
├── notifications_service.py (Notifications endpoint)
└── ancillaries_service.py   (Ancillaries endpoint)
```

## In-Memory Database

The "database" is a Python dictionary:
```python
class InMemoryStore:
    def __init__(self):
        self.data: Dict[str, any] = {}  # ← The database!
```

**Features:**
- ✅ Full CRUD operations (Create, Read, Update, Delete)
- ✅ Search and filtering  
- ✅ Fast (no disk I/O)
- ✅ Loads from ConfigMap at startup
- ⚠️  Data lost on pod restart

## Files

| File | Description | Lines |
|------|-------------|-------|
| `base_service.py` | Core in-memory DB + Flask REST API | 207 |
| `*_service.py` (×10) | Service entry points | ~15 each |
| `Dockerfile` | Multi-service image builder | 21 |
| `requirements.txt` | Python dependencies | 2 |
| `validate.sh` | Test validation script | 150 |
| **TOTAL** | | **~500 lines** |

## Testing

Run the validation script:
```bash
./validate.sh
```

Tests:
- ✅ In-memory database CRUD operations
- ✅ All 10 service files exist
- ✅ Service entry points are valid
- ✅ Dockerfile is correct

## Usage

### Local Testing
```bash
# Install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run a service
python3 flights_service.py
# Starts on http://localhost:3000

# Test it
curl http://localhost:3000/flights
curl -X POST http://localhost:3000/flights -d '{"flight_id":"FL999",...}'
```

### Docker
```bash
# Build image
docker build -t airlines-stateful-api:v0.1.0 .

# Run flights service
docker run -p 3000:3000 \
  -v /path/to/data:/api:ro \
  airlines-stateful-api:v0.1.0 \
  python flights_service.py

# Run bookings service (different container)
docker run -p 3001:3000 \
  -v /path/to/data:/api:ro \
  airlines-stateful-api:v0.1.0 \
  python bookings_service.py
```

### Kubernetes
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
          image: airlines-stateful-api:v0.1.0
          command: ["python", "flights_service.py"]  # ← Specify service
          volumeMounts:
            - name: data
              mountPath: /api
```

## API Endpoints

Each service exposes:
- `GET /{resource}` - List all
- `GET /{resource}/{id}` - Get one
- `POST /{resource}` - Create
- `PUT /{resource}/{id}` - Update
- `DELETE /{resource}/{id}` - Delete
- `GET /{resource}/search?field=value` - Search
- `GET /health` - Health check

Example for flights service:
```bash
GET    /flights
GET    /flights/FL123
POST   /flights
PUT    /flights/FL123
DELETE /flights/FL123
GET    /flights/search?origin=JFK
GET    /health
```

## How It Works

1. **Container starts** → Loads `base_service.py`
2. **Runs entry point** → e.g., `python flights_service.py`
3. **Entry point calls** → `run_service(resource='flights', id_field='flight_id', ...)`
4. **Base service**:
   - Loads data from `/api/api.json` (ConfigMap)
   - Stores in Python dict (RAM)
   - Creates Flask REST API
   - Listens on port 3000
5. **API requests** → Modify dict directly in memory
6. **Pod restarts** → Data reloads from ConfigMap

## Validation Results

```
✅ In-memory database works (Python dict)
✅ All 10 service files exist
✅ CRUD operations validated
✅ Service entry points are valid
✅ Dockerfile is correct

Ready to deploy!
```

## Summary

- **Architecture**: 1 image, 1 base service, 10 entry points
- **Database**: Python dict in RAM
- **Persistence**: None (demo/dev only)
- **Performance**: Fast (memory access)
- **Deployment**: Change `command:` in K8s to switch services
- **Status**: ✅ Validated and tested

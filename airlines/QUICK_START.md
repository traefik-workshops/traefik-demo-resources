# 🚀 QUICK START GUIDE

## What Was Done

1. ✅ **Fixed all MCP tools** - All 20 tools across 3 MCP servers now work
2. ✅ **Updated topic control** - Airlines/travel focused instead of government/education  
3. ✅ **Created stateful services** - 10 microservices with in-memory CRUD operations

## Deploy Immediately (Minimal Changes)

The MCP fixes are already applied to your Helm templates. To deploy:

```bash
cd /Users/zaidalbirawi/dev/ai-demo
terraform apply
```

**This gives you:**
- ✅ All MCP tools working (no more "Unknown tool" errors)
- ✅ Airlines-focused topic control
- ⚠️ Still using read-only mocks (bookings won't persist)

## Deploy Full Stateful Version (Recommended)

### 1. Build the stateful services image

```bash
cd /Users/zaidalbirawi/dev/traefik-resources/airlines/services
bash build.sh
```

This will:
- Generate all 10 service entry points
- Build Docker image: `ghcr.io/traefik-workshops/airlines-stateful-api:v0.1.0`
- Optionally push to registry

### 2. Update Helm values

Edit `/Users/zaidalbirawi/dev/traefik-resources/airlines/helm/values.yaml`:

```yaml
image:
  repository: ghcr.io/traefik-workshops/airlines-stateful-api
  tag: v0.1.0
  pullPolicy: IfNotPresent
```

### 3. Update service deployments

Each service needs to specify which Python script to run. Update the `args` in each deployment:

**Flights** (`helm/templates/flights/service.yaml`):
```yaml
containers:
  - name: api
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command: ["python", "flights_service.py"]  # ADD THIS
    args: []  # REMOVE the old args
```

**Bookings** (`helm/templates/bookings/service.yaml`):
```yaml
command: ["python", "bookings_service.py"]
```

**Check-in** (`helm/templates/checkin/service.yaml`):
```yaml
command: ["python", "checkin_service.py"]
```

Repeat for: `tickets`, `passengers`, `loyalty`, `pricing`, `baggage`, `notifications`, `ancillaries`

### 4. Deploy

```bash
cd /Users/zaidalbirawi/dev/ai-demo
terraform apply
```

### 5. Test

```bash
# Check health
kubectl get pods -n airlines

# Test flights API
kubectl port-forward -n airlines svc/flights-app 3000:3000
curl http://localhost:3000/flights
curl http://localhost:3000/health

# Test creating a booking
curl -X POST http://localhost:3000/bookings \
  -H "Content-Type: application/json" \
  -d '{"flight_id": "FL123", "passenger_id": "P001", "total_price": 450}'

# Verify it was created
curl http://localhost:3000/bookings
```

## Test MCP Tools in Dashboard

1. Open the airlines dashboard
2. Try these commands:

```
"Search for flights from JFK to LAX"
"Book me on flight FL123, passenger P001"
"Check me in for booking <booking-id>"
"What's my loyalty status for member L001?"
"Modify my booking to flight FL124"
"Cancel my booking"
```

All should work without errors and actually modify the database!

## Verify Live Data Changes

```bash
# Watch logs to see CRUD operations
kubectl logs -f -n airlines $(kubectl get pods -n airlines -l app=bookings-app -o name | head -1)

# You should see:
# "Created record: BK12345"
# "Updated record: BK12345"
# "Deleted record: BK12345"
```

## Troubleshooting

### "Unknown tool" errors still appearing
- Make sure you deployed the updated `ticketing-agent-mcp.yaml`
- Check MCP pod logs: `kubectl logs -n airlines ticketing-agent-mcp-xxxxx`
- Restart MCP pods: `kubectl delete pod -n airlines -l component=mcp`

### Services won't start with new image
- Check pod status: `kubectl get pods -n airlines`
- View logs: `kubectl logs -n airlines flights-app-xxxxx`
- Verify image exists: `docker images | grep airlines-stateful-api`
- Ensure ConfigMap is mounted at `/api/api.json`

### Bookings not persisting
- Check you're using the new image (not `api-server`)
- Verify command is set to correct Python script
- View service logs to confirm "+ Flask app is running"
- Test health endpoint: `curl http://<service>:3000/health`

### Data resets after pod restart
- This is EXPECTED behavior (in-memory storage)
- Data reloads from ConfigMap on each restart
- For persistence, see `services/README.md` for Redis/DB options

## Documentation

- **Complete details**: `IMPLEMENTATION_COMPLETE.md`
- **Service deployment**: `services/README.md`
- **MCP status**: `MCP_IMPLEMENTATION_STATUS.md`

## Summary

**Immediate deploy** (minimal): Just `terraform apply` - gets MCP fixes
**Full deploy** (recommended): Build image → Update values → Deploy - gets everything

**You're all set! 🎉**

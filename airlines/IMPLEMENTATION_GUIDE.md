# Airlines Demo - Quick Implementation Guide

This guide helps you quickly implement the remaining API services following the established pattern.

## Pattern Overview

Each API service consists of THREE files in `helm/templates/{service-name}/`:

1. **service.yaml** - Contains ConfigMaps (data + OAS), Deployment, and Service  
2. **api.yaml** - Contains API definition and IngressRoute
3. _(Optional)_ **guard.yaml** - MCP or API gateway policies

## Reference Implementation

✅ **Flights API** (`helm/templates/flights/`) is fully implemented and serves as the template.

Copy this structure for each new API service.

## Step-by-Step: Adding a New API

### 1. Create Directory Structure

```bash
cd /Users/zaidalbirawi/dev/traefik-resources/airlines/helm/templates
mkdir {service-name}  # e.g., mkdir loyalty
```

### 2. Copy Template Files

```bash
# Copy from flights as a starting point
cp flights/service.yaml {service-name}/service.yaml
cp flights/api.yaml {service-name}/api.yaml
```

### 3. Update service.yaml

Replace all instances of:
- `flights` → `{service-name}`
- `Flights` → `{Service Name}`
- `FL` flight prefix → appropriate prefix

Update the **data section** with service-specific mock data.

Update the **OpenAPI spec** with service-specific endpoints.

### 4. Update api.yaml

Replace:
- `flights-api` → `{service-name}-api`
- `flights-route` → `{service-name}-route`
- `airlines.flights` → `airlines.{service-name}`

Update **operation sets** based on who should access which endpoints.

### 5. Add Helpers (if new service)

Edit `templates/_helpers.tpl` and add:

```yaml
{{/*
{Service Name} API URL
*/}}
{{- define "airlines.{service-name}.apiUrl" -}}
https://{service-name}.{{ .Values.domain }}
{{- end }}

{{- define "airlines.{service-name}.hostMatch" -}}
Host(`{service-name}.{{ .Values.domain }}`)
{{- end }}
```

### 6. Test Locally

```bash
# Validate Helm chart
helm template airlines ./helm --namespace airlines

# Install
helm upgrade --install airlines ./helm -n airlines --create-namespace

# Verify
kubectl get pods -n airlines
kubectl get svc -n airlines
kubectl logs -n airlines -l app={service-name}-app
```

## Quick Reference: API Services to Create

### Priority 1 - Required for Ticketing Agent MCP

| Service | Endpoints Needed | Data Structure |
|---------|-----------------|----------------|
| **passengers** | GET /passengers/{id} | name, email, passport, loyalty_number|
| **loyalty** | GET /loyalty/members/{number}<br>POST /loyalty/miles/deduct | tier, miles, member_since|
| **pricing** | POST /pricing/calculate | base_fare, taxes, total |
| **bookings** | POST /bookings<br>GET /bookings/{id}<br>PUT /bookings/{id}<br>DELETE /bookings/{id} | booking_id, flight_id, passenger_id, status, price |
| **tickets** | POST /tickets/issue<br>POST /tickets/void | ticket_number, booking_id, passenger_id |
| **checkin** | POST /checkin/{booking_id}/seat<br>POST /checkin/{booking_id}/seat/auto<br>GET /checkin/{booking_id}/boarding-pass | seat, boarding_pass_url, barcode |
| **baggage** | POST /baggage/add<br>GET /baggage/track/{tag} | bag_tag, weight, fee, status |
| **ancillaries** | POST /ancillaries/meal<br>POST /ancillaries/seat-upgrade | type, price, description |
| **notifications** | POST /notifications/send | type, recipient, booking_id, sent_at |

### Priority 2 - For User Assistance MCP

| Service | Endpoints Needed |
|---------|-----------------|
| **disruptions** | GET /disruptions/flight/{id}<br>POST/disruptions/resolve |
| **compensations** | POST /compensations/calculate |
| **weather** | GET /weather/{airport} |

### Priority 3 - For Partner Assistance MCP

| Service | Endpoints Needed |
|---------|-----------------|
| **partners** | GET /partners<br>POST /partners/flights<br>PUT /partners/flights/{id} |
| **reports** | GET /reports/revenue/{partner_id} |

## Data Structure Templates

### Passengers API Data

```json
{
  "passengers": {
    "P12345": {
      "id": "P12345",
      "name": "John Smith",
      "email": "john.smith@example.com",
      "phone": "+1-555-0123",
      "passport": "US123456789",
      "loyalty_number": "FF987654",
      "special_needs": []
    }
  }
}
```

### Loyalty API Data

```json
{
  "members": {
    "FF987654": {
      "loyalty_number": "FF987654",
      "name": "John Smith",
      "tier": "Gold",
      "miles": 50000,
      "tier_qualifying_miles": 45000,
      "member_since": "2020-01-15"
    }
  }
}
```

### Bookings API Data

```json
{
  "bookings": {
    "BK789012": {
      "booking_id": "BK789012",
      "flight_id": "FL123",
      "passenger_id": "P12345",
      "status": "confirmed",
      "total_price": 405.00,
      "created_at": "2024-03-10T10:30:00Z",
      "seats": ["12B"]
    }
  }
}
```

## OpenAPI Spec Template

```yaml
openapi: "3.0.0"
info:
  version: 1.0.0
  title: {Service Name} API
  description: {Service description}
  contact:
    name: Traefik Airlines Engineering
servers:
  - url: {{ include "airlines.{service-name}.apiUrl" . }}

paths:
  /{resource}:
    get:
      summary: List {resources}
      operationId: list{Resources}
      tags:
        - {resource}
      responses:
        '200':
          description: List of {resources}
          content:
            application/json:
              schema:
                type: object

  /{resource}/{id}:
    get:
      summary: Get {resource} details
      operationId: get{Resource}ById
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: {Resource} details
        '404':
          description: {Resource} not found

components:
  schemas:
    {Resource}:
      type: object
      properties:
        id:
          type: string
        # ... other properties
```

## Time Estimates

- **First API** (copying template): 20-30 minutes
- **Subsequent APIs** (familiar with pattern): 10-15 minutes each
- **Total for 10 APIs Priority 1**: ~2-3 hours
- **MCP Server Integration Testing**: 1-2 hours

## Common Pitfalls to Avoid

1. ❌ **Forgetting to update ALL occurrences** of the service name
   - Search and replace is your friend: `flights` → `{new-service}`

2. ❌ **Invalid JSON in data ConfigMap**
   - Always validate with `jq` or a JSON validator
   ```bash
   cat service.yaml | yq eval '.data."api.json"' - | jq .
   ```

3. ❌ **Mismatched ports** between Service, Deployment, and IngressRoute
   - Always use port `3000` for the ghcr.io/traefik-workshops/api-server

4. ❌ **Missing labels** on Kubernetes resources
   - Always include `{{- include "airlines.labels" . | nindent 4 }}`

5. ❌ **Not updating _helpers.tpl**
   - Every new service needs URL helper functions

## Validation Checklist

Before considering an API "complete":

- [ ] ConfigMap with realistic mock data (at least 3-5 records)
- [ ] Complete OpenAPI 3.0 spec with all endpoints documented
- [ ] Deployment with correct image and volume mounts
- [ ] Service exposing port 3000
- [ ] API definition with appropriate operation sets
- [ ] IngressRoute with host-based routing
- [ ] Helpers added to _helpers.tpl
- [ ] Helm chart validates: `helm template airlines ./helm`
- [ ] Deployment succeeds: `helm upgrade --install ...`
- [ ] Pods are running: `kubectl get pods -n airlines`
- [ ] Endpoints are accessible from MCP server
- [ ] MCP server successfully calls the API

## Shell Script for Bulk Creation

To speed up creation of multiple services:

```bash
#!/bin/bash
# create-api-service.sh

SERVICE_NAME=$1
SERVICE_TITLE=$2

if [ -z "$SERVICE_NAME" ]; then
  echo "Usage: ./create-api-service.sh <service-name> <Service Title>"
  exit 1
fi

# Create directory
mkdir -p helm/templates/$SERVICE_NAME

# Copy templates
cp helm/templates/flights/service.yaml helm/templates/$SERVICE_NAME/service.yaml
cp helm/templates/flights/api.yaml helm/templates/$SERVICE_NAME/api.yaml

# Replace service name (macOS uses -i '')
sed -i '' "s/flights/$SERVICE_NAME/g" helm/templates/$SERVICE_NAME/*.yaml
sed -i '' "s/Flights/$SERVICE_TITLE/g" helm/templates/$SERVICE_NAME/*.yaml

echo "✅ Created $SERVICE_NAME API service skeleton"
echo "📝 Next steps:"
echo "   1. Edit helm/templates/$SERVICE_NAME/service.yaml - update data and OAS"
echo "   2. Edit helm/templates/_helpers.tpl - add URL helpers"
echo "   3. Test: helm template airlines ./helm"
```

Usage:

```bash
chmod +x create-api-service.sh
./create-api-service.sh loyalty "Loyalty"
./create-api-service.sh passengers "Passengers"
./create-api-service.sh pricing "Pricing"
# ... etc
```

## Next Steps After All APIs Created

1. **Update MCP Servers** to use real API endpoints
2. **Add MCP Gateway Policies** for tool authorization
3. **Add API Gateway Policies** for authentication
4. **Create Test Data** that tells a coherent story
5. **End-to-End Testing** using AIRLINES_TESTING_GUIDE.md
6. **Documentation** - Update STATUS.md as you complete each API

## Getting Help

If stuck:
- Reference the **Flights API** implementation
- Check the **gov** and **higher-ed** implementations for patterns
- Review **STATUS.md** for architecture decisions
- Consult **AIRLINES_TESTING_GUIDE.md** for what data is needed

Happy coding! ✈️

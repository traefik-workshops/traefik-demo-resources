# Traefik Airlines Demo

A comprehensive airlines platform demonstrating Traefik Hub's API Gateway, MCP Gateway, and API Portal capabilities with Keycloak OIDC authentication and real-time operational dashboards.

## Architecture

```text
                                    Internet
                                       │
                               ┌───────┴───────┐
                               │  Traefik Hub   │
                               │   (Gateway)    │
                               └───────┬───────┘
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
    ┌─────────┴──────────┐   ┌────────┴─────────┐   ┌─────────┴──────────┐
    │   Flight Ops       │   │  Passenger Svc    │   │   Airport Ops      │
    ├────────────────────┤   ├──────────────────-┤   ├────────────────────┤
    │                    │   │                    │   │                    │
    │  APIs:             │   │  APIs:             │   │  APIs:             │
    │  ├─ flights        │   │  ├─ bookings       │   │  ├─ checkin        │
    │  ├─ pricing        │   │  ├─ passengers     │   │  ├─ baggage        │
    │  └─ crew           │   │  └─ notifications  │   │  └─ gates          │
    │                    │   │                    │   │                    │
    │  MCP Server:       │   │  MCP Server:       │   │  MCP Server:       │
    │  └─ flight-ops-mcp │   │  └─ passenger-     │   │  └─ airport-       │
    │     (5 tools)      │   │     svc-mcp        │   │     ops-mcp        │
    │                    │   │     (5 tools)      │   │     (5 tools)      │
    │  Dashboard:        │   │                    │   │                    │
    │  ├─ flight-ops     │   │  ├─ passenger-     │   │  ├─ airport-       │
    │  │  (OIDC)         │   │  │  (OIDC)         │   │  │  (OIDC)         │
    │  └─ flight-board   │   │  └─ svc            │   │  └─ ops            │
    │     (public + SSE) │   │     (OIDC)         │   │     (OIDC)         │
    └────────────────────┘   └────────────────────┘   └────────────────────┘
              │                        │                        │
              └────────────────────────┼────────────────────────┘
                                       │
                          ┌────────────┴────────────┐
                          │                         │
                   ┌──────┴──────┐          ┌───────┴──────┐
                   │  API Portal │          │   Keycloak   │
                   │  (OIDC SSO) │          │  (Identity)  │
                   └─────────────┘          └──────────────┘
```

## Components

### 9 Mock APIs (Scalar Mock Server)

Each API runs as a `scalarapi/mock-server` instance serving an OpenAPI spec with `x-handler` mock responses.

| Domain | API | Bundle | Description |
|--------|-----|--------|-------------|
| **Flight Ops** | `flights.<domain>` | flight-ops | Schedules, routes, search, status |
| | `pricing.<domain>` | flight-ops | Fare rules, cabin classes, pricing |
| | `crew.<domain>` | flight-ops | Crew assignments, roster |
| **Passenger Svc** | `bookings.<domain>` | passenger-svc | Reservations, itineraries |
| | `passengers.<domain>` | passenger-svc | Profiles, frequent flyer |
| | `notifications.<domain>` | passenger-svc | Email, SMS, push notifications |
| **Airport Ops** | `checkin.<domain>` | airport-ops | Check-in, boarding passes |
| | `baggage.<domain>` | airport-ops | Bag tracking, claims |
| | `gates.<domain>` | airport-ops | Gate assignments, status |

### 3 MCP Servers (Streamable HTTP)

Each MCP server is a Python FastMCP instance that orchestrates the APIs in its domain.

| Server | Endpoint | Tools | Backend APIs |
|--------|----------|-------|-------------|
| **flight-ops-mcp** | `flight-ops-mcp.<domain>/mcp` | 5 | flights, pricing, crew |
| **passenger-svc-mcp** | `passenger-svc-mcp.<domain>/mcp` | 5 | bookings, passengers, notifications |
| **airport-ops-mcp** | `airport-ops-mcp.<domain>/mcp` | 5 | checkin, baggage, gates |

### 4 Dashboards

| Dashboard | Subdomain | Auth | Description |
|-----------|-----------|------|-------------|
| **Flight Board** | `board.<domain>` | Public | Real-time departures/arrivals with split-flap animation and SSE |
| **Flight Ops** | `flight-ops.<domain>` | OIDC (`flight-ops` group) | Flight, pricing, and crew management |
| **Passenger Svc** | `passenger-svc.<domain>` | OIDC (`passenger-svc` group) | Bookings, passengers, and notifications |
| **Airport Ops** | `airport-ops.<domain>` | OIDC (`airport-ops` group) | Check-in, baggage, and gate management |

Each protected dashboard uses Traefik Hub's OIDC middleware with Keycloak group claims. Admin users (`admins` group) can access all dashboards.

### API Portal

The API Portal (`portal.<domain>`) provides a developer portal with OIDC SSO for API discovery, documentation, and subscription management. APIs are organized into 3 bundles (Flight Ops, Passenger Svc, Airport Ops) with rate-limited access plans.

### Authentication

- **Keycloak** provides OIDC identity with realm `traefik`
- **JWT Auth** protects API access via JWKS validation
- **OIDC Middleware** protects operational dashboards with group-based claims
- **API Portal Auth** uses OIDC SSO for developer portal access

#### Dashboard Users

| Username | Group | Access |
|----------|-------|--------|
| `dispatcher` | `flight-ops` | Flight Ops dashboard |
| `agent` | `passenger-svc` | Passenger Services dashboard |
| `handler` | `airport-ops` | Airport Operations dashboard |
| `admin` | `admins` | All dashboards |

## Helm Chart

### Install

```bash
helm upgrade --install airlines ./airlines/helm \
  --set global.domain=<domain> \
  --set keycloak.oidc.issuerUrl=https://keycloak.<domain>/realms/traefik \
  --set keycloak.oidc.clientId=traefik \
  --set keycloak.oidc.clientSecret=<secret>
```

### Structure

```
airlines/helm/
├── Chart.yaml
├── values.yaml
├── files/dashboard/           # Dashboard HTML (Vue 3 + Tailwind)
│   ├── flight-board.html      # Public flight board with SSE
│   ├── flight-ops.html        # Flight operations dashboard
│   ├── passenger-svc.html     # Passenger services dashboard
│   └── airport-ops.html       # Airport operations dashboard
├── services/                  # Legacy (unused)
└── templates/
    ├── _helpers.tpl           # Shared helpers + reusable templates
    ├── api-auth.yaml          # JWT APIAuth + OIDC APIPortalAuth + Secret
    ├── bundles.yaml           # 3 APIBundles (flight-ops, passenger-svc, airport-ops)
    ├── manage-auth.yaml       # APIPlans + ManagedSubscriptions
    ├── portal.yaml            # APIPortal + IngressRoute
    ├── flight-ops/            # Flight Operations domain
    │   ├── api.yaml           # 3 APIs + IngressRoutes (flights, pricing, crew)
    │   ├── flights.yaml       # Flights OpenAPI ConfigMap + mock service
    │   ├── pricing.yaml       # Pricing OpenAPI ConfigMap + mock service
    │   ├── crew.yaml          # Crew OpenAPI ConfigMap + mock service
    │   └── mcp.yaml           # Flight Ops MCP server ConfigMap
    ├── passenger-svc/         # Passenger Services domain
    │   ├── api.yaml           # 3 APIs + IngressRoutes
    │   ├── bookings.yaml      # Bookings OpenAPI + mock service
    │   ├── notifications.yaml # Notifications OpenAPI + mock service
    │   ├── passengers.yaml    # Passengers OpenAPI + mock service
    │   └── mcp.yaml           # Passenger Svc MCP server ConfigMap
    ├── airport-ops/           # Airport Operations domain
    │   ├── api.yaml           # 3 APIs + IngressRoutes
    │   ├── checkin.yaml       # Check-in OpenAPI + mock service
    │   ├── baggage.yaml       # Baggage OpenAPI + mock service
    │   ├── gates.yaml         # Gates OpenAPI + mock service
    │   └── mcp.yaml           # Airport Ops MCP server ConfigMap
    └── dashboard/             # Dashboard deployments
        ├── flight-board.yaml  # Public board + SSE event server sidecar
        ├── flight-ops.yaml
        ├── passenger-svc.yaml
        └── airport-ops.yaml
```

### Flight Board SSE

The public flight board includes a Python sidecar (`ThreadingHTTPServer`) that provides a Server-Sent Events API for real-time flight updates:

```bash
# Add a flight
curl -X POST https://board.<domain>/api/board/flights \
  -H "Content-Type: application/json" \
  -d '{"flight_id":"TK999","airline":"TK","flight_number":"999","origin":"JFK","destination":"IST","status":"On-Time"}'

# Modify a flight
curl -X PUT https://board.<domain>/api/board/flights/TK999 \
  -H "Content-Type: application/json" \
  -d '{"status":"Boarding","gate":"A12"}'

# Delete a flight
curl -X DELETE https://board.<domain>/api/board/flights/TK999

# Reset all overlays
curl -X DELETE https://board.<domain>/api/board/reset
```

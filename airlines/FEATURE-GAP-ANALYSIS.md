# Traefik Hub Feature Gap Analysis

Features documented in Traefik Hub vs what's currently tested in the Hoppscotch collection.

## Currently Tested in Collection

| Feature | Section | Status |
|---------|---------|--------|
| OpenAPI Spec CRUD (all 9 services) | Airlines APIs | Covered — full GET/POST/PUT/PATCH/DELETE + search |
| API Versioning (v1 deprecated, v2 current) | Airlines APIs | Covered — deprecation + sunset header checks |
| OIDC Authentication (Keycloak JWT) | All sections | Covered — preRequestScript token fetch |
| Operation Sets (read/write/delete filtering) | Traefik Demo > Operation Sets | Covered — dispatcher, agent, handler, admin |
| API Bundles (cross-service access boundaries) | Traefik Demo > Operation Sets | Covered — dispatcher can't access gates, handler can't access flights |
| Plans & Quotas (rate limiting + quota exhaustion) | Traefik Demo > Plans & Quotas | Covered — analyst hits 429 |
| Request Body Schema Validation | Traefik Demo > Request Body Validation | Covered — missing fields, wrong types, invalid enums, null, empty |
| Method & Path Validation | Traefik Demo > Method & Path Validation | Covered — invalid method, path not in spec |
| Request Transformation (header injection) | Traefik Demo > Request Transformation | Covered — X-Served-By, X-Powered-By |
| WAF (Coraza — SQLi + XSS detection) | Traefik Demo > WAF | Covered — SQL injection, XSS attack patterns |

## Deployed in Helm Chart but NOT Tested

These features exist in the airlines Helm templates but have no corresponding Hoppscotch test:

### 1. API Portal (portal.yaml)
- **What's deployed:** APIPortal + APICatalogItem + APIPortalAuth with OIDC
- **What to test:** Portal endpoint responds, catalog items are visible, OIDC redirect works
- **Priority:** Medium — portal is a key demo point but requires browser interaction
- **Possible tests:** GET the portal URL and verify 200/302, check catalog API if available

### 2. API Deprecation Headers (v1 endpoints)
- **What's deployed:** Sunset + Deprecation headers on v1 APIVersions, Link header to v2
- **What's tested:** Deprecation + Sunset headers checked
- **Gap:** `Link` header pointing to successor version is NOT validated
- **Priority:** Low — easy to add a Link header check to existing v1 tests

### 3. StripPrefix Middleware (middlewares.yaml)
- **What's deployed:** strip-version-v1 and strip-version-v2 middlewares
- **What to test:** Verify path stripping works (v1/flights → /flights internally)
- **Priority:** Low — implicitly tested since v1/v2 routes already work

### 4. CORS Middleware (per-service api.yaml)
- **What's deployed:** Each API has CORS middleware (Access-Control-Allow-Origin: *, allowed methods/headers)
- **What to test:** OPTIONS preflight request returns correct CORS headers
- **Priority:** Medium — important for browser-based consumers, not yet validated

### 5. Multicluster / Uplinks (multicluster/)
- **What's deployed:** TraefikService WRR, Uplink CRDs (disabled by default)
- **What to test:** Only relevant when multicluster.enabled=true
- **Priority:** Low — conditional feature, not active on transit cluster

## Documented in Traefik Hub but NOT Deployed or Tested

These features exist in Traefik Hub docs but are NOT in the airlines demo at all:

### API Management Features

#### 6. Self-Service Subscriptions
- **Docs:** Consumers can request API access themselves through the portal
- **Airlines demo:** Only uses ManagedSubscription (admin-provisioned)
- **Demo value:** High — shows the consumer-facing workflow
- **Effort:** Medium — needs additional CRDs + a portal user flow

#### 7. APICatalogItem Visibility Controls
- **Docs:** Control which groups see which APIs in the portal catalog
- **Airlines demo:** Has APICatalogItem but doesn't demonstrate visibility filtering between groups
- **Demo value:** Medium — shows API discoverability controls
- **Effort:** Low — add tests that verify different users see different APIs in catalog

#### 8. External APIs in Catalog
- **Docs:** Register external (non-Traefik-routed) APIs in the catalog
- **Airlines demo:** All APIs are internal
- **Demo value:** Medium — relevant for hybrid API management scenarios
- **Effort:** Medium — need to add an external API CRD + catalog entry

### API Gateway Middlewares (Not Deployed)

#### 9. Rate Limiting (per-route, non-APIM)
- **Docs:** `rateLimit` middleware — token bucket rate limiting at the gateway level (separate from APIPlan)
- **Airlines demo:** Only uses APIPlan-based rate limiting
- **Demo value:** High — shows gateway-level vs APIM-level rate limiting difference
- **Possible test:** Add a rateLimit middleware to a route and verify 429 after threshold

#### 10. Circuit Breaker
- **Docs:** `circuitBreaker` middleware — stops forwarding when error ratio exceeds threshold
- **Airlines demo:** Not deployed
- **Demo value:** High — key resilience pattern for microservices
- **Possible test:** Trigger errors on a service and verify circuit opens (returns 503)

#### 11. Retry
- **Docs:** `retry` middleware — automatic retry of failed requests
- **Airlines demo:** Not deployed
- **Demo value:** Medium — resilience feature
- **Effort:** Low config, but hard to test deterministically

#### 12. InFlightReq (Concurrency Limiting)
- **Docs:** `inFlightReq` middleware — limits concurrent connections
- **Airlines demo:** Not deployed
- **Demo value:** Medium — load protection feature

#### 13. Compress
- **Docs:** `compress` middleware — gzip/brotli response compression
- **Airlines demo:** Not deployed
- **Demo value:** Low-Medium — performance optimization
- **Possible test:** Send Accept-Encoding: gzip header, verify Content-Encoding in response

#### 14. HTTP Cache
- **Docs:** `httpCache` middleware — response caching at the gateway
- **Airlines demo:** Not deployed
- **Demo value:** Medium — performance feature for read-heavy APIs
- **Possible test:** Two identical GETs, verify second is faster or has cache headers

#### 15. IP Allow List
- **Docs:** `ipAllowList` middleware — restrict access by source IP
- **Airlines demo:** Not deployed
- **Demo value:** Medium — common security requirement

#### 16. BasicAuth / DigestAuth
- **Docs:** `basicAuth` and `digestAuth` middlewares
- **Airlines demo:** Uses OIDC (JWT) only — no basic/digest auth
- **Demo value:** Low — OIDC is the modern approach, but basic auth is still common

#### 17. ForwardAuth
- **Docs:** `forwardAuth` middleware — delegate auth decisions to an external service
- **Airlines demo:** Not deployed (uses APIAuth with OIDC instead)
- **Demo value:** Medium — useful for custom auth logic integration

#### 18. RedirectRegex / RedirectScheme
- **Docs:** URL rewriting and HTTP→HTTPS redirects
- **Airlines demo:** Not deployed (TLS termination handled by ingress)
- **Demo value:** Low

#### 19. Error Pages
- **Docs:** Custom error page middleware
- **Airlines demo:** Not deployed
- **Demo value:** Medium — branded error responses are common in production

#### 20. Open Policy Agent (OPA)
- **Docs:** OPA middleware for policy-based authorization
- **Airlines demo:** Not deployed (uses operation sets instead)
- **Demo value:** High — popular in enterprise environments for fine-grained policy

#### 21. OAuth 2.1 Client Credentials / Token Introspection
- **Docs:** Machine-to-machine auth and token validation middlewares
- **Airlines demo:** Not deployed (all auth is user-facing OIDC)
- **Demo value:** Medium — relevant for service-to-service communication

#### 22. HMAC Authentication
- **Docs:** HMAC-based request signing middleware
- **Airlines demo:** Not deployed
- **Demo value:** Low-Medium — niche but used in some integrations (AWS-style signing)

### Tooling (Not Testable via Hoppscotch)

#### 23. Static Analyzer
- **Docs:** CLI tool for validating CRDs, linting, and diff reports (9 lint rules)
- **Airlines demo:** Not integrated
- **Demo value:** High — great for CI/CD pipeline demos
- **Note:** This is a CLI tool, not an API — can't be tested via Hoppscotch, but could be added to a GitHub Actions workflow

## Recommended Priorities for Next Collection Update

**High value, low effort (add to Traefik Demo next):**

1. **CORS Preflight** — Add an OPTIONS request test to verify CORS headers (already deployed)
2. **Link Header on Deprecated APIs** — Add Link header check to existing v1 tests
3. **Gateway-level Rate Limiting** — Deploy a `rateLimit` middleware and test separately from APIPlan
4. **Compress** — Deploy compress middleware, test with Accept-Encoding header

**High value, medium effort (future demo expansion):**

5. **Circuit Breaker** — Deploy and demonstrate resilience pattern
6. **OPA** — Deploy and show policy-based auth as alternative to operation sets
7. **Self-Service Subscriptions** — Show consumer-side portal workflow
8. **API Catalog Visibility** — Show different users see different APIs

**For CI/CD (not Hoppscotch):**

9. **Static Analyzer** — Add to GitHub Actions pipeline for CRD validation

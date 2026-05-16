# Spec: Auth-aware rate limiting (2026-05-15-9)

## Use case

Once browser authentication and PATs exist, the previous unauthenticated rate-limit gap should be moot in normal API traffic. Rate limiting still needs to be identity-aware and have safe fallbacks for public and malformed requests.

## Scope

In scope:
- Rate-limit keys based on authenticated user or PAT identity
- IP fallback for unauthenticated and malformed requests
- Public endpoint throttles
- Tests proving missing auth is still throttled

Out of scope:
- Distributed abuse protection beyond Rack::Attack
- Per-plan quota management
- CAPTCHA or bot detection

## Requirements

### 1) Replace token-string throttle keys with actor keys

**Problem:** The current throttle keys use the raw bearer token string, and requests without an `Authorization` header do not receive a throttle key.

**Fix:**
- Key authenticated API requests by PAT id, user id, or stable token prefix/digest id.
- Do not use or store raw token strings in Rack::Attack keys.
- Key browser requests by Devise user id where available.

**Test:**
- Requests authenticated with one PAT share one throttle bucket.
- Requests authenticated with different PATs have separate buckets.
- Throttle keys do not include raw bearer token values.

### 2) Add fallback throttles for unauthenticated requests

**Problem:** Missing-auth requests should not be unlimited, even though they will return `401`.

**Fix:**
- Add IP-based throttles for:
  - unauthenticated `/api/*`
  - unauthenticated `/admin/*`
  - Devise sign-in attempts
  - public health/webhook endpoints where appropriate
- Keep webhook throttling by IP.

**Test:**
- Repeated missing-token API requests eventually return `429`.
- Repeated invalid-token API requests eventually return `429`.
- Repeated admin requests without auth eventually return `429`.
- Health checks remain permissive enough for deploy probes.

### 3) Preserve useful response semantics

**Problem:** A rate limit should not hide auth failures until the throttle is exceeded, and once exceeded it should give clients retry information.

**Fix:**
- Before the limit is exceeded, missing/invalid auth returns `401`.
- After the limit is exceeded, return `429` with `Retry-After`.
- Keep JSON error format for API/admin endpoints.

**Test:**
- First invalid API request returns `401`.
- Request over the threshold returns `429`.
- `Retry-After` header is present.
- Response body is JSON.

### 4) Document operational knobs

**Problem:** Hard-coded limits are difficult to tune in production.

**Fix:**
- Move limits to named constants or environment-backed settings.
- Document default values and when to tune them.

**Test:**
- Defaults are applied when env vars are absent.
- Env overrides are parsed safely.

## Acceptance criteria

- [ ] Authenticated API throttles are keyed by actor, not raw token
- [ ] Missing/invalid auth requests are throttled by IP
- [ ] Web/browser auth flows have appropriate throttles
- [ ] Public endpoints retain safe, explicit limits
- [ ] Rate-limit responses include `Retry-After`
- [ ] Tests cover authenticated, unauthenticated, invalid-token, and public endpoint cases

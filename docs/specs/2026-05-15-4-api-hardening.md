# Spec: API hardening (2026-05-15-4)

## Use case

The API has no pagination, no rate limiting, and no request size limits. Under real usage these will cause memory exhaustion, abuse, and denial of service.

## Scope

In scope:
- Cursor or offset pagination on list endpoints
- Rate limiting via Rack::Attack
- Request body size limits
- Response size guard

Out of scope:
- OpenAPI/Swagger documentation (nice-to-have, not blocking)
- GraphQL or alternative API patterns
- Multi-tenant scoping

## Requirements

### 1) Pagination

**Problem:** `GET /api/v1/work_items`, `GET /api/v1/pipes`, and `GET /api/v1/costs` return all records. A queue with thousands of items will OOM.

**Fix:** Add `limit`/`offset` pagination with sensible defaults:

- Default `limit`: 50
- Max `limit`: 200
- Return pagination metadata in response:

```json
{
  "data": [...],
  "meta": {
    "total": 1234,
    "limit": 50,
    "offset": 0
  }
}
```

Apply to:
- `GET /api/v1/work_items` (highest priority — largest table)
- `GET /api/v1/costs` (can grow with trace events)
- `GET /api/v1/pipes` (lower volume, but consistent)

**Test:**
- Request with no params → returns first 50 items + meta.
- Request with `limit=10&offset=20` → returns items 21-30 + correct meta.
- Request with `limit=500` → clamped to 200.
- Request with `offset` beyond total → returns empty data array with correct total.

### 2) Rate limiting

**Problem:** No throttle exists. Any authenticated caller can hammer endpoints without limit.

**Fix:** Add `rack-attack` gem (already common in Rails). Configure:

- **API endpoints:** 300 requests/minute per service token
- **Admin endpoints:** 30 requests/minute per admin token
- **Webhook endpoint:** 60 requests/minute per IP

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("api/token", limit: 300, period: 60) do |req|
  req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if req.path.start_with?("/api/")
end

Rack::Attack.throttle("admin/token", limit: 30, period: 60) do |req|
  req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if req.path.start_with?("/admin/")
end

Rack::Attack.throttle("webhook/ip", limit: 60, period: 60) do |req|
  req.ip if req.path.include?("/webhooks/")
end
```

Return `429 Too Many Requests` with `Retry-After` header when throttled.

**Test:**
- 300 API requests in a minute → all succeed.
- 301st request → 429 with Retry-After header.
- Admin at 31 requests → 429.

### 3) Request body size limit

**Problem:** `POST /api/v1/work_items/:id/answer` accepts unbounded input in the `answer` field. A multi-MB payload would be stored in JSONB metadata.

**Fix:** Add Rack middleware or controller-level validation:

- Max request body: 1 MB globally
- Max `answer` field: 64 KB
- Max `spec_url` field: 2 KB
- Max individual tag value: 256 characters

```ruby
before_action :enforce_body_size_limit

def enforce_body_size_limit
  if request.content_length.to_i > 1.megabyte
    render json: { error: "Request body too large (max 1 MB)" }, status: :payload_too_large
    return
  end
end
```

Plus field-level validation in the answer and create actions.

**Test:**
- Answer with 100-byte body → accepted.
- Answer with 2 MB body → 413 Payload Too Large.
- Tag value with 300 characters → rejected with 422.

## Acceptance criteria

- [ ] All list endpoints return paginated results with meta (total, limit, offset)
- [ ] Default page size is 50, max is 200
- [ ] Rate limiting returns 429 with Retry-After header when exceeded
- [ ] Request bodies over 1 MB are rejected with 413
- [ ] Answer field over 64 KB is rejected with 422
- [ ] All scenarios have passing specs

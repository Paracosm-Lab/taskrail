# API Reference

Base path: `/api/v1`.

All examples assume a local server at `http://localhost:3000`.

## Queues

### List queues

```http
GET /api/v1/queues
```

Response shape:

```json
{
  "queues": [
    { "id": "...", "name": "Development", "slug": "development", "stages": ["intake", "decompose", "build", "test", "review", "done"] }
  ]
}
```

### Queue stages

```http
GET /api/v1/queues/:slug/stages
```

Returns the queue and each stage with adapter type and completion criteria.

## Work Items

### Create work item

```http
POST /api/v1/work_items
Content-Type: application/json
```

```json
{
  "queue": "development",
  "title": "Implement audit logging",
  "spec_url": "./docs/specs/audit-logging.md",
  "tags": { "risk": "medium", "repo": "api" }
}
```

The item starts at the first queue stage with status `pending`.

### List work items

```http
GET /api/v1/work_items
```

Filters:

- `queue`: queue slug.
- `stage`: stage name.
- `status`: one of `pending`, `claimed`, `blocked`, `waiting`, `completed`, `cancelled`.
- `tags[key]=value`: JSON tag filter.

Examples:

```bash
curl -s 'http://localhost:3000/api/v1/work_items?queue=development&status=pending'
curl -s 'http://localhost:3000/api/v1/work_items?tags[risk]=high'
```

### Show work item

```http
GET /api/v1/work_items/:id
```

Include traces:

```http
GET /api/v1/work_items/:id?traces=true
```

The response includes active claim summary, retry counts, regression counts, safe metadata, and escalation details when blocked.

### Answer blocked item

```http
POST /api/v1/work_items/:id/answer
Content-Type: application/json
```

```json
{ "answer": "Use bearer tokens. Do not rotate production credentials during this run." }
```

This stores `human_answer`, clears blocked metadata, logs `human_answer`, and returns the item to `pending`.

### Retry item

```http
POST /api/v1/work_items/:id/retry
```

Sets status back to `pending` and logs `manual_retry`.

### Cancel item

```http
POST /api/v1/work_items/:id/cancel
```

Sets status to `cancelled` and logs `cancelled`.

## Costs

### All-time costs

```http
GET /api/v1/costs
```

### Today's costs

```http
GET /api/v1/costs?period=today
```

### Work item costs

```http
GET /api/v1/costs/work_items/:id
```

Response shape:

```json
{
  "total_tokens_in": 0,
  "total_tokens_out": 0,
  "total_cost_cents": 0,
  "total_duration_ms": 0
}
```

## Digest

```http
GET /api/v1/digest?since=24h
```

The `since` window is parsed by `Engine::TimeWindowParser`. The CLI renders this endpoint as a human-readable operational digest.

```bash
bin/taskrail digest --since 24h
bin/taskrail digest --since 7d --json
```

## Streams

```http
GET /api/v1/stream
GET /api/v1/stream?queue=development
```

Server-sent events endpoint for dashboard data. It emits a `dashboard` event approximately every 2 seconds.

## Pipes

### List pipes

```http
GET /api/v1/pipes
```

### Show pipe

```http
GET /api/v1/pipes/:slug
```

Returns source queue/stage, target queue/stage, conditions, transforms, limits, and enabled state.

## GitHub Pull Request Webhook

```http
POST /api/v1/webhooks/github/pull_request
```

Supported actions:

- `opened`
- `reopened`
- `synchronize`
- `ready_for_review`

If `GITHUB_WEBHOOK_SECRET` is set, the controller verifies `X-Hub-Signature-256`.

Accepted pull request events create a `pr_review` work item with repository, PR number, branch, base branch, and head SHA tags.

## Admin Settings

Admin endpoints are under `/admin` and require admin authentication.

- `PUT /admin/log-level`
- `PUT /admin/trace-sample-rate`
- `GET /admin/circuit-breaker`
- `PUT /admin/circuit-breaker`
- `PUT /admin/maintenance`

These update runtime settings such as log level, trace sample rate, circuit breakers, and maintenance mode.

# StupidClaw Web UI Design

## Problem

The terminal UI gives quick status on what's running, but offers no way to deeply inspect what a work item produced — its artifacts, claims, reports, and transition history. Managing work items (retry, cancel, create) from the terminal is possible via the API but awkward. A web UI fills this gap: it's the inspection and management surface while the TUI remains the live status dashboard.

## Goals

- Inspect any work item's artifacts, claims, transition log, and children
- See the stage pipeline progress at a glance
- Retry failed or blocked work items; cancel running ones; create new ones
- Browse queues as Kanban boards (stages as columns, items as cards)
- View the pipe network topology

## Non-Goals

- Real-time streaming of claim execution (polling every 5s is sufficient)
- Multi-user access control or authentication (developer-only tool)
- Mobile-optimized layout
- Replacing the TUI (they serve different purposes)

## Tech Stack

Rails 8 native — Hotwire (Turbo Drive + Turbo Frames + Stimulus) with Tailwind CSS via `tailwindcss-rails`. Views added directly to the existing Rails app. The web UI reads from the database directly through existing models; it does not call the JSON API. The existing `/api/` routes are untouched.

**Rationale:** Rails 8 ships with Turbo/Stimulus. No separate build process, no CORS config, no second deploy target. Turbo Frames handle partial refreshes (auto-refreshing Kanban board). Stimulus handles small interactions (tab switching, JSON tree expand/collapse).

Asset pipeline: Propshaft (Rails 8 default). Tailwind CSS via `tailwindcss-rails` gem.

## Screens & Routes

| Route | Controller#action | Screen |
|---|---|---|
| `GET /` | `web/queues#index` | Queue list — all queues with item counts |
| `GET /queues/:slug` | `web/queues#show` | Kanban board for a queue |
| `GET /work_items/:id` | `web/work_items#show` | Work item detail |
| `GET /work_items/new` | `web/work_items#new` | New work item form |
| `POST /work_items` | `web/work_items#create` | Create work item |
| `POST /work_items/:id/retry` | `web/work_items#retry` | Retry current stage |
| `POST /work_items/:id/cancel` | `web/work_items#cancel` | Cancel work item |
| `GET /pipes` | `web/pipes#index` | Pipe network list |

All web routes live under a `Web` namespace in `app/controllers/web/`. This keeps them cleanly separated from the `Api::V1` namespace.

## Layout & Navigation

Persistent top bar on every page:
- **StupidClaw** logo (links to `/`)
- **Queue switcher** dropdown listing all queue slugs — switching navigates to that queue's Kanban board
- **Pipes** link to `/pipes`

No sidebar. No user menu. No settings. Breadcrumbs on work item detail: `queue_slug / work_item_title`.

Color scheme: dark, monospace-adjacent — matching the TUI's aesthetic (Catppuccin Mocha palette or equivalent via Tailwind custom colors). Not a standard Rails scaffold look.

## Queue List (`/`)

Simple grid of queue cards. Each card shows:
- Queue slug and name
- Count of pending / claimed / blocked / completed items
- Link to the Kanban board

Auto-refresh: none (static load is fine; stale counts are acceptable here).

## Kanban Board (`/queues/:slug`)

Each stage in the queue's `stages` array is a column, left to right. Work items are cards in their current stage's column.

**Card shows:** title, status badge (color-coded), time since created/updated.

**Board refresh:** The entire board is wrapped in a `<turbo-frame id="kanban-board" src="/queues/:slug/board" refresh="interval" data-turbo-refresh-interval="5000">`. A `web/queues#board` action renders just the columns partial. This gives live updates without a full page reload.

**Click a card:** Turbo Drive navigates to `/work_items/:id`.

**Column ordering:** Strictly follows `work_queue.stages` array order. The `done` stage column appears last and may be truncated to the 10 most recent completed items to avoid clutter.

**Empty state:** An empty column shows the stage name and a dimmed "empty" label — columns are always visible so the full pipeline is always apparent.

**New work item:** A "+ New" button in the first stage column opens the new work item form for this queue.

## Work Item Detail (`/work_items/:id`)

### Header

- Work item title (large)
- Status badge + current stage name + created timestamp + pipe origin (if pipe-created)
- **Retry** button (POST `/work_items/:id/retry`) — only shown if status is `blocked`, `claimed`, or `pending`
- **Cancel** button (POST `/work_items/:id/cancel`) — only shown if not `completed` or `cancelled`

### Pipeline Bar

Horizontal row of stage pills, left to right, matching the queue's stage sequence:
- **Completed stages:** green background
- **Current stage:** highlighted (orange if blocked, blue if claimed/pending)
- **Future stages:** dimmed grey

### Tabs

Four tabs below the pipeline bar:

#### Artifacts
List of all artifacts on this work item, sorted by `created_at` descending. Each artifact row shows:
- Kind (bold)
- Source stage and claim number
- A summary hint (e.g. "8 vulnerabilities" derived from data shape where obvious)
- **Pipe copy badge** if `claim_id` is nil (copied by a pipe)
- Collapsed by default; click to expand full JSON with syntax highlighting

JSON rendering: a simple recursive HTML renderer (no JS library needed) — `<details>/<summary>` tags styled with Tailwind, or a Stimulus controller for the expand/collapse toggle.

#### Claims
List of claims ordered by `created_at`. Each claim shows:
- Claim number, adapter type, status, started/ended timestamps
- Duration and cost (from associated trace)
- Report body (collapsible) — the agent's self-assessment summary
- Artifacts produced by this claim (kind badges)

#### Transition Log
Table: `From Stage | To Stage | Trigger | Timestamp | Details`. The `details` column is collapsible JSON for pipe-related log entries.

#### Children
Work items with `parent_id = this work item's id`. Each row shows title, queue, status, and whether it was created by a pipe or `spawn_work_items`. Links to their detail pages.

## Pipes (`/pipes`)

Simple table: one row per pipe.

| Name | From | → | To | Enabled | Last Fired |
|---|---|---|---|---|---|
| Security to Development | security_scan / classify_severity | → | development / intake | ✓ | 2m ago |

No topology diagram in v1. The pipes-design.md spec mentions a network topology view as a TUI feature — the web UI just needs the table for now.

## New Work Item Form

Minimal form:
- Queue (pre-filled from query param `?queue=slug`, dropdown of all queues)
- Title (text input)
- Spec URL (text input)
- Tags (JSON textarea, optional)

On submit: creates the work item at the queue's first stage, redirects to its detail page.

## Retry & Cancel

**Retry:** Finds the current claim (if any), marks it `failed`, creates a new pending claim. The work item stays at the current stage with status `pending`. Implemented in the model or a thin service — mirrors what the engine does on retry.

**Cancel:** Sets work item status to `cancelled`. Dependent claims are left as-is (not killed — engine processes stop naturally on next tick).

Both are `<form method="post">` with a CSRF token — no JavaScript required.

## Auto-Refresh

Only the Kanban board auto-refreshes (every 5s via Turbo Frame). The work item detail page does not auto-refresh — it's a point-in-time snapshot. A manual "Refresh" link in the header is sufficient.

## File Structure

```
app/
  controllers/
    web/
      queues_controller.rb      # index, show, board
      work_items_controller.rb  # show, new, create, retry, cancel
      pipes_controller.rb       # index
  views/
    web/
      layouts/
        application.html.erb    # top nav, Tailwind, Turbo
      queues/
        index.html.erb          # queue list
        show.html.erb           # kanban board page
        _board.html.erb         # turbo-frame partial (auto-refreshed)
        _column.html.erb        # one stage column
        _card.html.erb          # one work item card
      work_items/
        show.html.erb           # detail page
        new.html.erb            # create form
        _pipeline.html.erb      # stage pipeline bar
        _artifacts.html.erb     # artifacts tab
        _claims.html.erb        # claims tab
        _transition_log.html.erb
        _children.html.erb
      pipes/
        index.html.erb          # pipes table
    layouts/
      web.html.erb              # (or reuse application layout)
  javascript/
    controllers/
      tabs_controller.js        # Stimulus: tab switching
      json_tree_controller.js   # Stimulus: expand/collapse artifact JSON
```

## Testing

- **Request specs** for each controller action (status codes, key content assertions)
- **System specs** for the Kanban board refresh and work item detail tab switching
- No unit tests for views — the controller specs cover the data shapes

## Out of Scope (v1)

- Real-time streaming (WebSockets)
- Artifact diffing between claims
- Inline editing of work item metadata
- Network topology diagram for pipes
- Pagination (add when counts grow; start with sensible limits in queries)

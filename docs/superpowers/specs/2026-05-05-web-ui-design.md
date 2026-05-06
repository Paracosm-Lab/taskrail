# StupidClaw Web UI Design

## Problem

The terminal UI gives quick status on what's running, but offers no way to deeply inspect what a work item produced — its artifacts, claims, reports, and transition history. Managing work items (retry, cancel, create) from the terminal is possible via the API but awkward. A web UI fills this gap: it's the inspection and management surface while the TUI remains the live status dashboard.

## Goals

- Inspect any work item's artifacts, claims, transition log, and children
- See the stage pipeline progress at a glance
- Retry blocked work items; cancel running ones; create new ones
- Browse queues as Kanban boards (stages as columns, items as cards)
- View the pipe network topology

## Non-Goals

- Real-time streaming of claim execution (polling every 5s is sufficient)
- Multi-user access control or authentication (developer-only tool)
- Mobile-optimized layout
- Replacing the TUI (they serve different purposes)
- Answering escalation questions from the web UI (v1 — use the API directly)

## Tech Stack

Rails 8 native — Hotwire (Turbo Drive + Turbo Frames + Stimulus) with Tailwind CSS via `tailwindcss-rails`. Views added directly to the existing Rails app. The web UI reads from the database directly through existing models; it does not call the JSON API. The existing `/api/` routes are untouched.

**Rationale:** No separate build process, no CORS config, no second deploy target. Turbo Frames handle partial refreshes (auto-refreshing Kanban board). Stimulus handles small interactions (tab switching, JSON tree expand/collapse).

Asset pipeline: Propshaft (Rails 8 default). Tailwind CSS via `tailwindcss-rails` gem.

## Setup: Enabling Views in an API-Only App

The app was generated with `--api`, which sets `config.api_only = true` in `application.rb`. This disables sessions, flash, CSRF protection, cookies middleware, and the asset pipeline. Adding views requires reversing this for the web layer.

**Changes required before any views code:**

1. Set `config.api_only = false` in `config/application.rb` (or selectively re-enable middleware — but toggling the flag is simpler since the API controllers use `ActionController::API` explicitly)
2. Add gems to `Gemfile`:
   ```ruby
   gem "turbo-rails"
   gem "stimulus-rails"
   gem "tailwindcss-rails"
   gem "propshaft"  # likely already present in Rails 8
   ```
3. Run installers: `rails turbo:install stimulus:install tailwindcss:install`
4. CSRF: web controllers inherit from `ActionController::Base` which has CSRF enabled by default. API controllers already use `ActionController::API` and are unaffected.

**`Web::BaseController`** — all web controllers inherit from this, not from `ApplicationController` (which is `ActionController::API`):

```ruby
# app/controllers/web/base_controller.rb
module Web
  class BaseController < ActionController::Base
    layout "web"
  end
end
```

This gives web controllers sessions, flash, CSRF, layouts — everything the API controllers don't have.

## Screens & Routes

| Route | Controller#action | Screen |
|---|---|---|
| `GET /` | `web/queues#index` | Queue list — all queues with item counts |
| `GET /queues/:slug` | `web/queues#show` | Kanban board for a queue |
| `GET /queues/:slug/board` | `web/queues#board` | Turbo Frame partial: board columns only |
| `GET /work_items/:id` | `web/work_items#show` | Work item detail |
| `GET /work_items/new` | `web/work_items#new` | New work item form |
| `POST /work_items` | `web/work_items#create` | Create work item |
| `POST /work_items/:id/retry` | `web/work_items#retry` | Set status pending, log manual_retry |
| `POST /work_items/:id/cancel` | `web/work_items#cancel` | Cancel work item |
| `GET /pipes` | `web/pipes#index` | Pipe network list |

All web routes live under a `Web` namespace in `app/controllers/web/`. This keeps them cleanly separated from the `Api::V1` namespace.

## Layout & Navigation

Persistent top bar on every page:
- **StupidClaw** logo (links to `/`)
- **Queue switcher** dropdown listing all queue slugs — switching navigates to that queue's Kanban board
- **Pipes** link to `/pipes`

No sidebar. No user menu. No settings. Breadcrumbs on work item detail: `queue_slug / work_item_title`.

Web layout lives at `app/views/layouts/web.html.erb`. `Web::BaseController` sets `layout "web"`.

Color scheme: dark, monospace-adjacent — matching the TUI's aesthetic (Catppuccin Mocha palette or equivalent via Tailwind custom colors). Not a standard Rails scaffold look.

## Work Item Statuses

Six statuses exist: `pending`, `claimed`, `blocked`, `waiting`, `completed`, `cancelled`.

Color mapping for badges and pipeline bars:

| Status | Color |
|---|---|
| pending | blue |
| claimed | amber |
| blocked | red |
| waiting | purple (waiting on children) |
| completed | green |
| cancelled | grey |

## Queue List (`/`)

Simple grid of queue cards. Each card shows:
- Queue slug and name
- Counts for all active statuses: pending / claimed / blocked / waiting
- Total completed count
- Link to the Kanban board

Auto-refresh: none (static load is fine; stale counts are acceptable here).

## Kanban Board (`/queues/:slug`)

Each stage in the queue's `stages` jsonb array is a column, left to right. Work items are cards in their current `stage_name` column. Stage order comes from `work_queue.stages` — there is no separate stages table; `stage_configs` holds configuration per stage but ordering is always from `stages`.

**Card shows:** title, status badge (color per table above), time since created/updated.

**Board refresh:** A Stimulus `auto-refresh` controller on the `<turbo-frame>` calls `this.element.reload()` on a 5-second interval. The frame's `src` points to `/queues/:slug/board`, which renders just the columns partial.

```html
<turbo-frame id="kanban-board"
             src="/queues/<%= @queue.slug %>/board"
             data-controller="auto-refresh"
             data-auto-refresh-interval-value="5000">
  <!-- columns render here -->
</turbo-frame>
```

```javascript
// app/javascript/controllers/auto_refresh_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { interval: { type: Number, default: 5000 } }
  connect() {
    this.timer = setInterval(() => this.element.reload(), this.intervalValue)
  }
  disconnect() { clearInterval(this.timer) }
}
```

**Click a card:** Turbo Drive navigates to `/work_items/:id`.

**Column ordering:** Strictly follows `work_queue.stages` array order. The `done` stage column is truncated to the 10 most recent completed items.

**Empty state:** An empty column shows the stage name and a dimmed "empty" label — columns are always visible so the full pipeline is always apparent.

**New work item:** A "+ New" button in the first stage column opens the new work item form for this queue.

## Work Item Detail (`/work_items/:id`)

**Stage inference:** The pipeline bar determines completed/current/future by finding the work item's `stage_name` in `work_queue.stages`. Stages before it are completed, the matching index is current, stages after are future. There is no per-stage completed flag.

### Header

- Work item title (large)
- Status badge (using color table above) + current stage name + created timestamp
- Pipe origin badge if `pipe_id` is present: `via pipe_slug`
- **Retry** button (POST `/work_items/:id/retry`) — shown only if status is `blocked` or `waiting`
- **Cancel** button (POST `/work_items/:id/cancel`) — shown only if status is not `completed` or `cancelled`

### Pipeline Bar

Horizontal row of stage pills, left to right, matching the queue's `stages` array:
- **Completed stages:** green background
- **Current stage:** color matches status (red=blocked, amber=claimed, blue=pending, purple=waiting)
- **Future stages:** dimmed grey

### Tabs

Four tabs below the pipeline bar, switched by a Stimulus `tabs` controller:

#### Artifacts
List of all artifacts on this work item, sorted by `created_at` descending. Each artifact row shows:
- Kind (bold, monospace)
- Source: which stage and which claim by sequential index (1st claim, 2nd claim, etc. — claims have no number column; index by `created_at` order)
- A summary hint where derivable (e.g. array length: "8 vulnerabilities")
- **Pipe copy badge** if `claim_id` is nil (copied by a pipe, not produced by a claim)
- Collapsed by default; click to expand full JSON with syntax highlighting

JSON rendering: `<details>/<summary>` tags styled with Tailwind — no JavaScript required.

#### Claims
List of claims ordered by `created_at`, labeled 1st, 2nd, 3rd by position. Each claim shows:
- Sequential number, adapter type, status, started/ended timestamps
- Duration (formatted as "3.2s") and cost in dollars (from associated trace: `total_cost_cents / 100.0`)
- Report body (collapsible `<details>`) — the agent's self-assessment summary
- Kind badges for artifacts produced by this claim

#### Transition Log
Table: `From Stage | To Stage | Trigger | Timestamp | Details`. The `details` column is a collapsible `<details>` for entries with non-null details JSON (pipe triggers, limit hits, etc.).

#### Children
Work items with `parent_id = this work item's id`. Each row: title, queue slug, status badge, pipe slug (if `pipe_id` present, else "spawned"). Links to their detail pages.

## Pipes (`/pipes`)

Simple table: one row per pipe.

| Name | From | → | To | Enabled | Last Fired |
|---|---|---|---|---|---|
| Security to Development | security_scan / classify_severity | → | development / intake | ✓ | 2m ago |

"Last Fired" derived from the most recent `transition_logs` entry with `trigger: "pipe"` and `details->>"pipe_slug" = pipe.slug`.

No topology diagram in v1.

## New Work Item Form

Minimal form:
- Queue (pre-filled from query param `?queue=slug`, dropdown of all queues)
- Title (text input, required)
- Spec URL (text input, required)
- Tags (key-value pairs: repeated `name` + `value` inputs, not a raw JSON textarea)

On submit: creates the work item at the queue's first stage, redirects to its detail page. Validation errors re-render the form with field-level messages.

## Retry & Cancel

**Retry:** Mirrors the existing `Api::V1::WorkItemsController#retry` behavior — sets the work item `status` to `pending` and logs a `manual_retry` transition. The engine creates a new claim on its next tick. Does not touch existing claims directly.

**Cancel:** Sets work item status to `cancelled`. Dependent claims are left as-is (not killed — engine processes stop naturally on their next tick).

Both are plain `<form method="post">` with Rails CSRF tokens — no JavaScript required.

## Auto-Refresh

Only the Kanban board auto-refreshes (every 5s via the `auto-refresh` Stimulus controller on the Turbo Frame). The work item detail page does not auto-refresh — it's a point-in-time snapshot. A manual "↻ Refresh" link in the breadcrumb bar reloads the page.

## File Structure

```
app/
  controllers/
    web/
      base_controller.rb        # < ActionController::Base, layout "web"
      queues_controller.rb      # index, show, board
      work_items_controller.rb  # show, new, create, retry, cancel
      pipes_controller.rb       # index
  views/
    layouts/
      web.html.erb              # top nav, Tailwind, Turbo script tags
    web/
      queues/
        index.html.erb          # queue list
        show.html.erb           # kanban board page (contains turbo-frame)
        _board.html.erb         # rendered by board action inside turbo-frame
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
  javascript/
    controllers/
      tabs_controller.js        # Stimulus: tab switching
      auto_refresh_controller.js  # Stimulus: turbo-frame polling
```

## Testing

- **Request specs** for each controller action (status codes, key content present)
- **System spec** for the work item detail tab switching (Stimulus interaction)
- No unit tests for views — controller specs cover data shapes

## Out of Scope (v1)

- Real-time streaming (WebSockets)
- Artifact diffing between claims
- Inline editing of work item metadata
- Network topology diagram for pipes
- Pagination (add when counts grow; queries use sensible limits)
- Answering escalation questions from the UI
- Error pages styled to match the web UI theme

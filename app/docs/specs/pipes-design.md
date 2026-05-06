# Pipes: Composable Queue Data Flow

## Problem

TaskRail queues run in isolation. A security scan produces findings. A remediation queue could act on those findings. Today the only connection between them is `spawn_work_items` — an agent-decided, ad-hoc mechanism buried in report bodies. You can't look at the system and see how queues connect. You can't declare "when security scan finishes, feed the results into remediation." The network topology is invisible until runtime.

## Solution

Pipes are a first-class primitive. A pipe declares a data flow between two queues: when a source queue reaches a specific stage, evaluate conditions against its artifacts, and if they match, create a new work item in the target queue with copied artifacts.

Pipes are fire-and-forget. The source queue advances regardless of what happens downstream. Pipes carry data, not control flow.

## Pipe Config Schema

Pipes live in `config/pipes/*.yml`, one file per pipe. Synced to the database by `db/seeds.rb` the same way queues are.

```yaml
# config/pipes/security_to_remediation.yml
name: Security to Remediation
slug: security_to_remediation

from:
  queue: security_scan
  stage: classify_severity

when:
  artifact_kind: severity_report
  conditions:
    - field: "findings[].severity"
      operator: includes
      value: ["critical", "high"]

to:
  queue: development
  stage: intake

transform:
  artifacts:
    - from_kind: severity_report
      to_kind: input_findings
    - from_kind: vulnerability_scan
      to_kind: input_scan
  tags:
    risk: high
    source_pipeline: security_scan
  title_template: "Fix: {{source.title}} — high-severity findings"

limits:
  max_children: 5
```

### Fields

**from** — Source trigger point.
- `queue`: source queue slug (must exist)
- `stage`: stage name that triggers evaluation. The pipe fires after all predicates pass and the work item transitions out of this stage. (Must exist in the source queue's stage list.)

**when** — Conditions for firing. All conditions must pass (AND logic).
- `artifact_kind`: which artifact to evaluate conditions against
- `conditions`: list of field/operator/value checks against the artifact's data

Three operators:
- `includes` — array field contains any of the specified values
- `equals` — field matches value exactly
- `exists` — field is present and non-null

**Field path syntax:** Dot-separated keys with `[]` as an array iterator. `findings[].severity` means "for each element in the `findings` array, read the `severity` key." For `includes`, the condition passes if any array element's field value is in the specified value list. For `exists`, it passes if any element has the field. Nested objects use dots: `meta.source.type`. No wildcards, no deep recursion — one level of `[]` max. Implemented as a simple split-and-walk, not a JSONPath library.

If `when` is omitted, the pipe fires unconditionally when the source stage is exited.

**to** — Target destination.
- `queue`: target queue slug (must exist)
- `stage`: stage name to place the new work item (defaults to the target queue's first stage)

**transform** — How to shape the downstream work item.
- `artifacts`: list of artifact kind mappings. `from_kind` is required. `to_kind` is optional — if omitted, the original kind name is preserved.
- `tags`: static tags merged onto the new work item. Auto-tags (`pipe_slug`, `source_queue`, `source_work_item`) are always added.
- `title_template`: interpolation template for the new work item's title. Supports `{{source.title}}`, `{{source.id}}`, `{{pipe.name}}`.

**limits** — Per-pipe safety controls. Can only be tighter than global limits.
- `max_children`: maximum work items this pipe can create from a single source item.

## Pipe Model

```ruby
# Table: pipes
#   id: uuid (pk)
#   name: string (not null)
#   slug: string (unique index, not null)
#   from_queue_id: uuid (fk -> work_queues, not null)
#   from_stage: string (not null)
#   to_queue_id: uuid (fk -> work_queues, not null)
#   to_stage: string
#   when_config: jsonb
#   transform_config: jsonb
#   limits: jsonb
#   enabled: boolean (default: true)
#   created_at, updated_at: timestamps

class Pipe < ApplicationRecord
  belongs_to :from_queue, class_name: "WorkQueue"
  belongs_to :to_queue, class_name: "WorkQueue"

  validates :name, :slug, :from_stage, presence: true
  validates :slug, uniqueness: true
  validate :from_stage_exists_in_queue
  validate :to_stage_exists_in_queue
end
```

### Work Item Changes

Add `pipe_id` column to `work_items`:
- `pipe_id: uuid (fk -> pipes, nullable)`
- Set when the work item was created by a pipe
- Null for direct creation or agent-initiated `spawn_work_items`

## PipeEvaluator Service

The PipeEvaluator runs inside the TransitionManager's `advance` method, after the existing `spawn_cross_queue_items!` call, within the same transaction.

```
TransitionManager#advance
  ├── update work_item stage_name, status, retry_count
  ├── spawn_cross_queue_items!  (existing agent-initiated spawns)
  ├── PipeEvaluator.call(work_item, from_stage)  (new)
  └── create transition_log
```

### Evaluation Logic

```ruby
class PipeEvaluator
  def self.call(work_item:, from_stage:)
    return unless engine_config.pipes_enabled?

    depth = calculate_pipe_depth(work_item)
    return if depth >= engine_config.max_pipe_depth

    pipes = Pipe.where(from_queue: work_item.work_queue, from_stage: from_stage, enabled: true)

    pipes.each do |pipe|
      evaluate_pipe(pipe, work_item, depth)
    end
  end
end
```

**Step 1: Find matching pipes.** Query for enabled pipes whose `from_queue` and `from_stage` match.

**Step 2: Check global limits.** Calculate pipe depth by walking the `parent_id` chain. Each ancestor with a non-null `pipe_id` increments the depth. If depth >= `max_pipe_depth`, skip all pipes and log a warning.

**Step 3: For each matching pipe:**

1. **Evaluate `when` conditions.** Load the artifact matching `when.artifact_kind` from the work item. Run each condition against the artifact's `data` field. All conditions must pass. If no `when` block, the pipe fires unconditionally.

2. **Check per-pipe limits.** Count existing work items with this `pipe_id` and this `parent_id`. If >= `pipe.limits.max_children` (or global `max_children_per_pipe` if pipe doesn't specify), skip and log.

3. **Apply transform.** Copy specified artifacts as new `Artifact` records on the downstream work item (details below). Build tags by merging pipe tags + auto-tags. Interpolate title template.

4. **Create work item.** In the target queue, at the target stage (or first stage if not specified), with `parent_id` set to the source work item, `pipe_id` set to the pipe, status `pending`.

5. **Log.** Create transition_log on the source work item with trigger `"pipe"` and details: `{ pipe_slug, target_queue, created_item_id }`.

### Depth Calculation

```ruby
def calculate_pipe_depth(work_item)
  depth = 0
  current = work_item
  while current.parent_id.present?
    current = WorkItem.find(current.parent_id)
    depth += 1 if current.pipe_id.present?
  end
  depth
end
```

Depth counts pipe-created ancestors only. A work item created by `spawn_work_items` (pipe_id nil) does not increment depth. This keeps the depth counter focused on declared pipe chains, not ad-hoc spawns.

**Performance note:** This walks the parent chain with one query per ancestor. At `max_depth: 3`, that's at most 3-4 sequential queries. Acceptable given the low max depth. If max_depth is ever raised significantly, replace with a recursive CTE.

## Artifact Copying

When a pipe fires, the transform block specifies which artifacts to carry forward.

**Copy, not move.** Source artifacts stay on the source work item. The downstream item gets new `Artifact` records with duplicated `data`.

**Claim-less artifacts.** Copied artifacts have `claim_id: nil`. They're input data, not output from a claim. The `AssignmentBuilder` already includes `upstream_artifacts` in the assignment payload — copied artifacts appear there naturally.

**Schema change required:** The existing `artifacts` table has `claim_id` as NOT NULL. This requires a migration to make `claim_id` nullable and updating the `Artifact` model to `belongs_to :claim, optional: true`. Existing code that assumes `artifact.claim` is always present must be checked — the `AssignmentBuilder#upstream_artifacts` query uses `where.not(claim_id: @claim.id)` which still works with NULL claim_ids.

**Kind remapping.** If `to_kind` is specified, the copied artifact's `kind` is set to that value. Otherwise, the original kind is preserved.

**Missing artifacts are not errors.** If the transform specifies `from_kind: severity_report` but no artifact of that kind exists on the source item, skip silently. The downstream queue's predicates will catch missing input if it matters.

**Multiple artifacts of same kind.** If the source has multiple artifacts of the specified kind (from retries), copy only the most recent one (by `created_at`).

## Global Engine Config

```yaml
# config/engine.yml
pipes:
  max_depth: 3
  max_children_per_pipe: 5
  enabled: true
```

This file is loaded via a Rails initializer into an `EngineConfig` object (new) that provides `pipes_enabled?`, `max_pipe_depth`, and `max_children_per_pipe`. Simple YAML load with defaults — no runtime reloading needed. Toggle `enabled` and restart.

**max_depth: 3** — A pipe can trigger a pipe can trigger a pipe, but no deeper. Four queues in the chain max.

**max_children_per_pipe: 5** — One source work item can create at most 5 items through any single pipe. Individual pipes can set lower via their own `limits.max_children` but cannot exceed this.

**enabled: true** — Global kill switch. Flip to false and all pipe evaluation stops. Agent-initiated `spawn_work_items` continues to work. No code change, no deploy.

When a limit is hit, the PipeEvaluator logs a transition_log entry with trigger `"pipe_limit_reached"` and details explaining which limit was hit. No error, no block — the source work item advances normally regardless.

## Coexistence with spawn_work_items

Both mechanisms coexist. They serve different purposes.

**Pipes** (declared in config):
- Predictable, repeatable flows between queues
- Visible in system topology
- Carry artifacts with kind remapping
- Subject to depth/fan-out limits
- Evaluated by the engine, not the agent

**spawn_work_items** (in agent reports):
- Emergent, context-dependent flows
- Not visible until runtime
- Pass data via `spec_inline` text
- Decided by the agent, executed by the engine

**Depth checking addition:** The existing `spawn_cross_queue_items!` in TransitionManager also checks global `max_depth` using the same depth calculation. This closes the current gap where spawn has no recursion protection.

No breaking changes to the existing spawn mechanism.

## Observability

### Transition Logs

- Source work item gets trigger `"pipe"` with details: `{ pipe_slug, target_queue, created_item_id }`
- Created work item gets trigger `"pipe_received"` with details: `{ pipe_slug, source_queue, source_work_item_id }`
- Limit hits logged as trigger `"pipe_limit_reached"` with details: `{ pipe_slug, limit_type, current_count, max }`

### API Endpoints

- `GET /api/pipes` — List all pipes with from/to queues, enabled status. The network topology view.
- `GET /api/pipes/:slug` — Single pipe detail with recent activity: last fired, items created count, last limit hit.

### Work Item Enrichment

The existing `GET /api/work_items/:id` response adds:
- `pipe_slug` — which pipe created this item (null if direct or spawn)
- `piped_from` — source work item ID
- `piped_children` — items this work item created via pipes

### TUI (future)

Network topology view (queues as nodes, pipes as edges) deferred to a separate TUI spec.

## Validation

The seeds file validates pipe definitions at sync time:

- `from.queue` slug must reference an existing queue
- `from.stage` must exist in the source queue's stages array
- `to.queue` slug must reference an existing queue
- `to.stage` (if specified) must exist in the target queue's stages array
- `slug` must be unique across all pipes
- `limits.max_children` cannot exceed global `max_children_per_pipe`
- For same-queue pipes, `to.stage` must come after `from.stage` in the stage sequence (prevents guaranteed loops)

**Idempotency:** Before creating a downstream work item, check `WorkItem.exists?(pipe_id: pipe.id, parent_id: work_item.id)`. If a pipe has already fired for this source item, skip. This prevents duplicates if `advance` is called twice due to retries or race conditions.

**spec_url:** Pipe-created work items get `spec_url` set to `"pipe://#{pipe.slug}/#{source_work_item.id}"`.

Invalid pipe definitions fail the seed with a clear error message. The system will not start with broken pipe config.

## Example Pipes

### Security scan to remediation
```yaml
name: Security to Remediation
slug: security_to_remediation
from:
  queue: security_scan
  stage: classify_severity
when:
  artifact_kind: severity_report
  conditions:
    - field: "findings[].severity"
      operator: includes
      value: ["critical", "high"]
to:
  queue: development
  stage: intake
transform:
  artifacts:
    - from_kind: severity_report
      to_kind: input_findings
    - from_kind: vulnerability_scan
      to_kind: input_scan
  tags:
    risk: high
    source_pipeline: security_scan
  title_template: "Fix: {{source.title}} — high-severity findings"
limits:
  max_children: 5
```

### Operations to runbook generation
```yaml
name: Ops to Runbook Generation
slug: ops_to_runbook
from:
  queue: operations
  stage: assess_instrumentation
when:
  artifact_kind: instrumentation_assessment
  conditions:
    - field: "gaps[].missing_runbook"
      operator: exists
to:
  queue: operations
  stage: map_runbooks
transform:
  artifacts:
    - from_kind: instrumentation_assessment
    - from_kind: failure_clusters
  tags:
    source_pipeline: operations
  title_template: "Runbook: {{source.title}}"
```

### Incident replay to readiness scoring
```yaml
name: Incident to Readiness
slug: incident_to_readiness
from:
  queue: post_incident_replay
  stage: done
when:
  artifact_kind: response_evaluation
  conditions:
    - field: "grade"
      operator: includes
      value: ["D", "F"]
to:
  queue: incident_readiness
  stage: inventory_services
transform:
  artifacts:
    - from_kind: response_evaluation
      to_kind: input_evaluation
    - from_kind: incident_updates
      to_kind: input_updates
  tags:
    triggered_by: incident
  title_template: "Readiness audit triggered by {{source.title}}"
```

## Updated Primitives

With pipes, the full primitive set:

| Primitive | Purpose |
|-----------|---------|
| Cookbook | Documented use case pattern |
| Queue | Owns a workflow as a linear stage sequence |
| Pipe | Declared data flow between queues |
| Work Item | Unit of work moving through a queue |
| Stage | One step in a queue's workflow |
| Stage Config | Adapter, model, predicates, prompt for a stage |
| Claim | Single agent execution attempt |
| Artifact | Structured data produced by a claim or copied by a pipe |
| Report | Agent's self-assessment of a claim |
| Predicate | Independent verification of stage completion |
| Transition | Logged state change |
| Trace | Cost and telemetry for a claim |

The system describes any workflow network with these 12 primitives. Cookbooks document patterns, queues execute them, pipes compose them.

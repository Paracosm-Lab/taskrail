# Configuration

Taskrail behavior is mostly configured through YAML. The engine reads queue, stage, adapter, predicate, pipe, and runtime settings from files and persists queue definitions into Postgres.

## Queue Files

Queue definitions live in `config/queues/*.yml`.

A queue file defines:

- `name`
- `category`
- `slug`
- ordered `stages`
- queue-level `config`
- per-stage `stage_configs`

Example skeleton:

```yaml
name: Development
category: Development
slug: development
stages:
  - intake
  - decompose
  - build
  - test
  - review
  - done
config:
  default_max_retries: 3
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  build:
    adapter_type: fake
    allowed_skills: [clone_repo, create_branch, edit_files, run_tests]
    forbidden_skills: [deploy, merge_main, mutate_database]
    max_retries: 3
    escalation_target: block_and_notify
    completion_criteria: [branch_created, report_present]
    agent_prompt: Implement the assigned chunk according to spec and produce a branch artifact.
    timeout_seconds: 600
```

## Stage Config Fields

### adapter_type

Supported values:

- `fake`
- `shell_script`
- `inline_claude`
- `codex`
- `docker_compose`

### allowed_skills and forbidden_skills

These fields document and constrain what the stage assignment may do. `Engine::AssignmentBuilder` expands allowed skill names through `Engine::SkillLoader` and passes forbidden skill names through to adapters.

### completion_criteria

Completion criteria are predicate names. All predicates for a stage must pass for the stage to advance.

Examples:

```yaml
completion_criteria:
  - tests_passed
  - lint_clean
  - coverage_not_decreased
```

### agent_prompt

Prompt can be inline text or a file reference:

```yaml
agent_prompt: file://cookbooks/prompts/migration_safety/scan_impact.md
```

### adapter_config

Adapter-specific settings. Common fields include:

- `input_artifact_kind`
- `output_artifact_kind`
- `fixture_app`
- `commands`
- `compose_file`
- `working_directory`
- `command`
- `args`
- `poll_command`
- `poll_args`

## Adapter Configuration

### fake

Used for deterministic development and tests. No external process required.

### shell_script

Runs configured shell commands. Example:

```yaml
adapter_type: shell_script
adapter_config:
  output_artifact_kind: test_results
  commands:
    - name: unit tests
      artifact: test_results
      command: bundle exec rspec
```

### inline_claude

Runs local Claude CLI synchronously and parses the response into normalized artifacts and reports.

Common fields:

```yaml
adapter_type: inline_claude
model_override: claude-sonnet-4-20250514
adapter_config:
  input_artifact_kind: impact_map
  output_artifact_kind: rollback_plan
  fixture_app: cookbooks/fixtures/apps/migration_safety_app
```

### codex

Submits work asynchronously to Codex CLI and polls later with `Engine::AsyncClaimChecker`.

Common fields:

```yaml
adapter_type: codex
adapter_config:
  command: codex
  args: [exec, --json]
  poll_command: codex
  poll_args: [status, --json]
  working_directory: .
  output_artifact_kind: branch
```

### docker_compose

Starts a Docker Compose process and tracks it through async claim state and heartbeat messages.

Common fields:

```yaml
adapter_type: docker_compose
adapter_config:
  compose_file: cookbooks/docker-compose.yml
  working_directory: .
```

## Pipes

Pipes live in `config/pipes/*.yml`.

Example:

```yaml
name: Security to Development
slug: security_to_development
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
  tags:
    risk: high
  title_template: "Fix: {{source.title}} - high-severity findings"
limits:
  max_children: 5
```

Supported pipe condition operators:

- `includes`
- `equals`
- `exists`

Supported field pattern includes array traversal such as `findings[].severity`.

## Engine Settings

`config/engine.yml` controls pipe safeguards:

```yaml
pipes:
  max_depth: 3
  max_children_per_pipe: 5
  enabled: true
```

These limits prevent runaway cross-queue spawning.

## Runtime Settings

Admin endpoints can update runtime behavior:

- Log level.
- Trace sample rate.
- Circuit breakers.
- Maintenance mode.

See [API Reference](./api.md#admin-settings).

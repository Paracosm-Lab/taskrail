# Cookbook Spec: Test Coverage Backfill

## Use Case

A startup codebase with spotty test coverage. Models, controllers, and services that shipped fast with no specs. Everyone agrees tests need to happen. Nobody wants to write them.

StupidClaw scans the codebase, identifies untested code paths, generates specs, runs them, and iterates until they pass. Human review before merge.

## Queue: `test_backfill`

### Stages

```
scan_coverage → identify_gaps → generate_tests → run_tests → human_review → done
```

### Stage Details

**scan_coverage** (Haiku)
- Adapter: `inline_claude`
- Input: repository path, test framework config (RSpec, minitest, etc.)
- Task: Run coverage tool (`simplecov`, `coverage.py`, etc.), parse the report, produce a structured map of files and their coverage percentages
- Artifact: `coverage_map` — `{ files: [{ path, coverage_pct, uncovered_lines: [range] }] }`
- Predicate: `coverage_map_produced` — artifact exists with non-empty file list
- Why Haiku: parsing tool output, no reasoning needed

**identify_gaps** (Sonnet)
- Adapter: `inline_claude`
- Input: coverage_map artifact, repository code
- Task: Read the uncovered files, classify each gap by type (model validation, controller action, service method, error path, edge case), prioritize by risk (public API > internal helper), group into testable units
- Artifact: `test_plan` — `{ units: [{ file, method, gap_type, risk, description }] }`
- Predicate: `test_plan_produced` — artifact exists with at least one unit
- Why Sonnet: needs to read code and make judgment calls about risk

**generate_tests** (Sonnet)
- Adapter: `inline_claude`
- Input: test_plan artifact, source files, existing test patterns in repo
- Task: For each unit in the plan, write a spec file following the project's existing test conventions. Match style, fixtures, factory patterns. Output as file contents with paths.
- Artifact: `generated_tests` — `{ specs: [{ path, content }] }`
- Predicate: `tests_generated` — artifact has at least one spec
- Why Sonnet: needs to understand existing test patterns and write correct code
- Note: Working directory should be the target repo. Agent needs `read_repo` skill.

**run_tests** (shell_script)
- Adapter: `shell_script`
- Input: generated_tests artifact
- Task: Write spec files to disk, run the test suite, capture output
- Artifact: `test_results` — `{ passed: bool, output, failures: [] }`
- Predicate: `tests_passed` (existing)
- On failure: regress to `generate_tests` with failure output as context (max 3 regression loops)

**human_review** (gate)
- Adapter: `fake`
- Blocks for human approval of generated tests before merge

### Queue Config

```yaml
name: Test Coverage Backfill
slug: test_backfill
stages:
  - scan_coverage
  - identify_gaps
  - generate_tests
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  scan_coverage:
    adapter_type: shell_script
    allowed_skills: [run_coverage]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [coverage_map_produced]
    agent_prompt: file://prompts/backfill_scan_coverage.md
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: coverage_map
  identify_gaps:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [test_plan_produced]
    agent_prompt: file://prompts/backfill_identify_gaps.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: test_plan
  generate_tests:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [tests_generated]
    agent_prompt: file://prompts/backfill_generate_tests.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: generated_tests
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Write generated spec files to disk and run the test suite. Report pass/fail with output.
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: test_results
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review generated tests before merge.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `coverage_map_produced` — checks for `coverage_map` artifact with non-empty `files` array
- `test_plan_produced` — checks for `test_plan` artifact with non-empty `units` array
- `tests_generated` — checks for `generated_tests` artifact with non-empty `specs` array

### E2E Test Fixtures

Use StupidClaw's own codebase as the target. Pick a model or service with known gaps, or create a small fixture app with deliberately untested code in `test/fixtures/apps/untested_app/`.

### Regression Loop

When `run_tests` fails, it regresses to `generate_tests`. The regeneration prompt receives the failure output so it can fix the broken specs. Max 3 loops — if tests still fail after 3 attempts, block for human intervention.

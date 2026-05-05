# Cookbook Spec: Logging Consistency Audit

## Use Case

Your services log in five different formats. One uses structured JSON. One uses `Rails.logger.info "thing happened"`. One uses `puts`. One doesn't log at all. When an incident happens, you grep five different patterns across three services and still can't reconstruct what happened.

StupidClaw scans every log statement, categorizes by format and usefulness, drafts a logging standard based on what's already working, then rewrites the worst offenders. Human review before merge.

## Queue: `logging_audit`

### Stages

```
scan_log_statements → assess_quality → draft_standard → draft_fixes → run_tests → human_review → done
```

### Stage Details

**scan_log_statements** (Haiku)
- Adapter: `inline_claude`
- Input: repository path
- Task: Find every log statement across the codebase:
  - `Rails.logger.*`, `Logger.*`, `console.log`, `puts`, `print`, `p`, `pp`
  - Custom logger calls
  - Sentry breadcrumbs and context calls (these are a form of logging)
  - Structured vs unstructured output
  - Log level usage (debug/info/warn/error/fatal)
  - For each: file, line, format type, what it logs, log level
- Artifact: `log_inventory` — `{ statements: [{ file, line, logger, level, format: "structured"|"unstructured"|"debug_output", content, context_present: bool }], summary: { total, by_format: {}, by_level: {}, by_service: {} } }`
- Predicate: `log_inventory_produced` — artifact exists
- Why Haiku: pattern matching and extraction

**assess_quality** (Sonnet)
- Adapter: `inline_claude`
- Input: log_inventory artifact, source code
- Task: Score the logging quality per file/module:
  - **Structured**: does the log include key-value pairs or just a string?
  - **Contextual**: does it include request_id, user_id, operation, or other correlation fields?
  - **Appropriate level**: is `info` used for debugging? Is `error` used for expected conditions?
  - **Useful**: would this log actually help debug an incident, or is it noise?
  - Identify the best logging patterns already in the codebase (these become the standard)
  - Identify the worst (these get fixed first)
- Artifact: `logging_assessment` — `{ best_patterns: [], worst_offenders: [], scores_by_file: {}, recommended_standard: {} }`
- Predicate: `logging_assessed` — artifact exists
- Why Sonnet: needs to make judgment calls about log usefulness

**draft_standard** (Sonnet)
- Adapter: `inline_claude`
- Input: logging_assessment artifact
- Task: Draft a logging standard based on the best patterns already in the codebase:
  - Required fields for each log level (e.g., error logs must include request_id, operation, error_class)
  - Format specification (structured JSON with specific keys)
  - Level guidelines (when to use info vs warn vs error)
  - Anti-patterns to avoid
  - Example log lines for common scenarios (request handling, job processing, external API calls, error recovery)
- Artifact: `logging_standard` — `{ standard: { format, required_fields_by_level, guidelines, examples, anti_patterns } }`
- Predicate: `standard_drafted` — artifact exists
- Why Sonnet: synthesizing a standard from observed patterns

**draft_fixes** (Sonnet)
- Adapter: `inline_claude`
- Input: logging_standard artifact, logging_assessment (worst offenders), source code
- Task: Rewrite the worst offending log statements to match the standard:
  - Replace `puts`/`p`/`pp` with structured logger calls
  - Add context fields to bare string logs
  - Fix inappropriate log levels
  - Remove noise logging (e.g., `puts "here"` debug leftovers)
  - Start with highest-impact files (controllers, jobs, service objects)
- Artifact: `log_patches` — `{ patches: [{ file, original, replacement, reason }] }`
- Predicate: `fixes_drafted` (reuse from error handling audit)
- Why Sonnet: needs to understand what context is available at each log site

**run_tests** (shell_script)
- Adapter: `shell_script`
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_fixes`

**human_review** (gate)

### Queue Config

```yaml
name: Logging Consistency Audit
slug: logging_audit
stages:
  - scan_log_statements
  - assess_quality
  - draft_standard
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_log_statements:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [log_inventory_produced]
    agent_prompt: file://prompts/logging_scan_statements.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: log_inventory
  assess_quality:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [logging_assessed]
    agent_prompt: file://prompts/logging_assess_quality.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: logging_assessment
  draft_standard:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [standard_drafted]
    agent_prompt: file://prompts/logging_draft_standard.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: logging_standard
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/logging_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: log_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply logging patches and run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review logging standard and fixes.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `log_inventory_produced` — checks for `log_inventory` artifact
- `logging_assessed` — checks for `logging_assessment` artifact
- `standard_drafted` — checks for `logging_standard` artifact

### E2E Test Fixtures

Create a fixture app in `test/fixtures/apps/bad_logging/` with:
- A controller using `puts params.inspect`
- A job using `Rails.logger.info "processing user"`  (no user_id, no structured data)
- A service using structured JSON logging correctly (the "good" pattern to learn from)
- An error handler using `Rails.logger.error e.message` (no stack trace, no context)
- A module with no logging at all in critical paths

### Output

The logging standard artifact becomes a reusable reference — future audit runs diff against it, and the `assess_quality` stage can score against the standard instead of discovering patterns from scratch.

# Cookbook Spec: API Documentation Sync

## Use Case

You have 40 API endpoints. The docs cover 12 of them and 3 of those are wrong. A new engineer joins and asks "where are the docs?" and you say "check the code." Every customer integration starts with a Slack thread.

StupidClaw scans your routes, controllers, and serializers, generates OpenAPI specs, diffs against existing documentation, flags the gaps, and drafts the missing docs. Human review before publishing.

## Queue: `api_docs_sync`

### Stages

```
scan_endpoints → diff_existing_docs → draft_documentation → validate_examples → human_review → done
```

### Stage Details

**scan_endpoints** (Haiku)
- Adapter: `inline_claude`
- Input: repository path, framework type (Rails, Express, Django, etc.)
- Task: Parse routes, controllers, serializers/presenters to build a complete endpoint inventory:
  - HTTP method + path
  - Controller#action
  - Request params (path, query, body) with types
  - Response shape (from serializer or actual response)
  - Authentication requirements
  - Any inline documentation that already exists
- Artifact: `endpoint_inventory` — `{ framework, endpoints: [{ method, path, controller, params: [], response_shape: {}, auth, existing_docs }] }`
- Predicate: `endpoint_inventory_produced` — artifact exists with at least one endpoint
- Why Haiku: parsing route files and serializers is extraction, not reasoning

**diff_existing_docs** (Sonnet)
- Adapter: `inline_claude`
- Input: endpoint_inventory artifact, existing documentation (OpenAPI/Swagger, README, wiki, etc.)
- Task: Compare the inventory against existing docs:
  - **Missing**: endpoints with no documentation at all
  - **Stale**: documented endpoints where params, response shapes, or auth have changed
  - **Incorrect**: docs that describe behavior that doesn't match the code
  - **Undocumented behavior**: error responses, pagination, rate limits not mentioned in docs
- Artifact: `docs_diff` — `{ missing: [], stale: [], incorrect: [], undocumented_behavior: [], coverage_pct }`
- Predicate: `docs_diff_produced` — artifact exists
- Why Sonnet: needs to compare code against prose and make judgment calls about correctness

**draft_documentation** (Sonnet)
- Adapter: `inline_claude`
- Input: docs_diff artifact, endpoint_inventory, existing docs format
- Task: For each gap, draft the documentation in the project's existing format (OpenAPI YAML, Markdown, whatever they use):
  - Match existing style and structure
  - Include request/response examples with realistic data
  - Document error responses
  - Note auth requirements
  - Add deprecation notices where applicable
- Artifact: `draft_docs` — `{ format, files: [{ path, content, change_type: "new"|"update" }] }`
- Predicate: `docs_drafted` — artifact has at least one file
- Why Sonnet: needs to write clear documentation that matches project conventions

**validate_examples** (shell_script or inline_claude)
- Adapter: `shell_script`
- Input: draft_docs artifact
- Task: If the docs include request/response examples, validate them:
  - Do the request examples parse correctly?
  - Do the response shapes match what the serializer actually produces?
  - Can the OpenAPI spec be parsed without errors? (`swagger-cli validate`)
- Artifact: `validation_results` — `{ valid: bool, errors: [] }`
- Predicate: `docs_validated` — artifact exists with `valid: true`
- On failure: regress to `draft_documentation` with validation errors

**human_review** (gate)
- Adapter: `fake`
- Blocks for human approval before publishing

### Queue Config

```yaml
name: API Documentation Sync
slug: api_docs_sync
stages:
  - scan_endpoints
  - diff_existing_docs
  - draft_documentation
  - validate_examples
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_endpoints:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [endpoint_inventory_produced]
    agent_prompt: file://prompts/docs_scan_endpoints.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: endpoint_inventory
  diff_existing_docs:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [docs_diff_produced]
    agent_prompt: file://prompts/docs_diff_existing.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: docs_diff
  draft_documentation:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [docs_drafted]
    agent_prompt: file://prompts/docs_draft.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: draft_docs
  validate_examples:
    adapter_type: shell_script
    allowed_skills: [run_validation]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [docs_validated]
    agent_prompt: Validate OpenAPI spec and request/response examples. Report pass/fail.
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: validation_results
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review generated API documentation.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `endpoint_inventory_produced` — checks for `endpoint_inventory` artifact with non-empty endpoints
- `docs_diff_produced` — checks for `docs_diff` artifact
- `docs_drafted` — checks for `draft_docs` artifact with at least one file
- `docs_validated` — checks for `validation_results` artifact with `valid: true`

### E2E Test Fixtures

Use StupidClaw's own API as the target — it has routes, controllers, and serializers but likely incomplete documentation. Or create a fixture app with documented and undocumented endpoints.

### Recurring Use

This queue is designed to run periodically (e.g., after every sprint). Feed it the same repo and it diffs against the docs it generated last time, catching any new endpoints or changes that haven't been documented.

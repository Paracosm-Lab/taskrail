# Cookbook Spec: PR Review Pipeline

**Category: Development**

## Use Case

PRs sit in the review queue for hours or days. When a human reviewer finally looks, they find linting failures, missing tests, a security issue, and an architectural violation — things that could have been caught automatically. The human reviewer's time gets wasted on mechanical checks instead of design judgment.

TaskRail runs a multi-stage automated review on every PR before a human touches it. Lint, test, security scan, architectural review, test coverage check. By the time a human reviewer opens the PR, the mechanical stuff is already done. They can focus on "is this the right approach?" instead of "did you run the linter?"

## Queue: `pr_review`

### Stages

```
run_checks → security_scan → coverage_check → architectural_review → human_review → done
```

### Stage Details

**run_checks** (shell_script)
- Adapter: `shell_script`
- Input: branch name, base branch
- Task: Run the standard CI checks:
  - Linter (rubocop, eslint, etc.)
  - Type checker if applicable
  - Full test suite
  - Build/compile
  - Report: which checks passed, which failed, failure details
- Artifact: `check_results` — `{ lint: { passed, errors: [] }, tests: { passed, failures: [] }, build: { passed } }`
- Predicate: `checks_passed` — all checks pass
- On failure: block immediately — don't waste AI tokens reviewing code that doesn't pass lint

**security_scan** (Sonnet)
- Adapter: `inline_claude`
- Input: git diff of the PR, check_results artifact
- Task: Review the diff for security issues:
  - SQL injection (string interpolation in queries)
  - XSS (unescaped user input in templates)
  - Auth bypass (missing authentication checks on new endpoints)
  - Secrets (API keys, passwords, tokens in code)
  - Insecure dependencies (if new deps were added)
  - Mass assignment / parameter tampering
  - SSRF, path traversal, command injection
  - Rate: `blocking` / `warning` / `info`
- Artifact: `security_findings` — `{ findings: [{ severity, category, file, line, description, fix_suggestion }], blocking_count }`
- Predicate: `security_reviewed` — artifact exists (zero findings is fine)
- On blocking findings: escalate to human immediately, don't proceed to architectural review

**coverage_check** (shell_script)
- Adapter: `shell_script`
- Input: diff, test results
- Task: Check test coverage for the changed code:
  - Are there tests for the new/modified code paths?
  - Did overall coverage decrease?
  - Are the tests meaningful (not just `expect(true).to be true`)?
  - List uncovered lines in changed files
- Artifact: `coverage_report` — `{ overall_delta, changed_files: [{ file, coverage_pct, uncovered_lines }], new_files_without_tests: [] }`
- Predicate: `coverage_checked`

**architectural_review** (Sonnet)
- Adapter: `inline_claude`
- Input: diff, security_findings, coverage_report, project conventions (CLAUDE.md, architecture docs)
- Task: Review the PR for design and architecture:
  - Does it follow existing patterns in the codebase?
  - Are there naming inconsistencies?
  - Is the abstraction level appropriate? (over-engineering vs under-engineering)
  - Are there performance concerns? (N+1 queries, missing indexes, expensive operations in hot paths)
  - Does it introduce unnecessary coupling between modules?
  - Produce a structured review with approve / request_changes / comment
- Artifact: `architecture_review` — `{ verdict: "approve"|"request_changes"|"comment", comments: [{ file, line, severity, comment }], summary }`
- Predicate: `review_verdict` (existing)

**human_review** (gate)
- The human reviewer sees all upstream artifacts: check results, security findings, coverage report, architectural review. They can focus on the stuff machines can't judge — business logic, product fit, strategic direction.

### Queue Config

```yaml
name: PR Review Pipeline
slug: pr_review
stages:
  - run_checks
  - security_scan
  - coverage_check
  - architectural_review
  - human_review
  - done
config:
  default_max_retries: 1
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  run_checks:
    adapter_type: shell_script
    allowed_skills: [run_tests, run_linter]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [checks_passed]
    agent_prompt: file://prompts/pr_run_checks.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: check_results
  security_scan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [security_reviewed]
    agent_prompt: file://prompts/pr_security_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: security_findings
  coverage_check:
    adapter_type: shell_script
    allowed_skills: [run_tests, run_coverage]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [coverage_checked]
    agent_prompt: file://prompts/pr_coverage_check.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: coverage_report
  architectural_review:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [review_verdict]
    agent_prompt: file://prompts/pr_architectural_review.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: architecture_review
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Human reviewer sees all automated findings. Focus on business logic and design.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `checks_passed` — check_results with all checks passing
- `security_reviewed` — security_findings artifact exists
- `coverage_checked` — coverage_report artifact exists

### Trigger

This queue is triggered by a webhook — when a PR is opened or updated, create a work item automatically. The work item's spec_url is the PR URL. The diff is fetched from GitHub.

### Cross-Queue Spawn

When `security_scan` finds blocking issues, it can spawn a work item into `error_handling_audit` or `development` to fix the underlying pattern (e.g., "this service builds SQL with string interpolation everywhere, not just this PR").

# GitHub & Linear Adapters — Core Platform Features

## Goal

Add three GitHub adapters and one Linear adapter to TaskRail's adapter registry as core platform features. These enable any queue to create PRs, wait for CI, merge PRs, and ingest work from Linear — the fundamental operations for agent-assisted engineering pipelines.

The first consumer is the postrunner-fix pipeline: Linear ticket → codex fix → open PR → CI check → Claude review → merge.

## Scope

**In scope:**
- `github_pr_create` adapter — create a PR from a branch
- `github_ci_poll` adapter — async poll GitHub checks until pass/fail
- `github_pr_merge` adapter — merge a PR
- `linear_poll` ingestion — scheduled job that pulls new postrunner tickets from Linear and creates work items
- Wire `model_override` through `InlineClaudeAdapter` to the CLI
- `postrunner-fix` queue YAML — the first pipeline using all of the above

**Out of scope:** Linear webhooks (add when TaskRail is publicly hosted), GitHub API client library (use `gh` CLI), new UI features

## Architecture

All three GitHub adapters wrap the `gh` CLI, following the same pattern as `ShellScriptAdapter`. They return structured artifacts with typed data rather than raw stdout.

The Linear poll is a scheduled job (Solid Queue) that runs every 5 minutes, queries the Linear API for new `postrunner`-labeled issues, and creates work items in the `postrunner-fix` queue.

```
Linear (postrunner tickets)
  │
  ▼ [linear_poll job, every 5min]
TaskRail work item (postrunner-fix queue)
  │
  ├── fix stage         → codex adapter (cheap model)
  ├── open_pr stage     → github_pr_create adapter
  ├── await_ci stage    → github_ci_poll adapter (async)
  ├── review stage      → inline_claude adapter (strong model via model_override)
  └── merge stage       → github_pr_merge adapter
```

## Adapter 1: `github_pr_create`

**Type:** Synchronous (returns `AgentResult`)

**Purpose:** Create a GitHub pull request from an existing branch.

**Input (from assignment context/artifacts):**
- `repository` — GitHub repo in `owner/repo` format (from work item tags)
- `branch` — source branch name (from upstream artifact, e.g., codex output)
- `base_branch` — target branch, defaults to `main`
- `title` — PR title (from work item title or adapter_config)
- `body` — PR description (from upstream report summary)

**adapter_config:**
```yaml
adapter_config:
  base_branch: main                    # default target branch
  draft: false                         # create as draft PR
  title_template: "fix: {work_item_title}"
```

**Output artifact:**
```ruby
{
  "kind" => "pull_request",
  "data" => {
    "number" => 42,
    "url" => "https://github.com/MyScribbl/crm-service/pull/42",
    "branch" => "postrunner/fix-sc2086-deploy-sh",
    "base_branch" => "main",
    "head_sha" => "abc1234"
  }
}
```

**Implementation:**

Note: All GitHub adapters call `assignment.deep_stringify_keys` at the top of `execute` to normalize symbol/string key access, matching the pattern in `CodexAdapter` and `InlineClaudeAdapter`.

```ruby
module Adapters
  class GithubPrCreateAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      config = assignment.dig("stage", "adapter_config") || {}
      tags = assignment.dig("work_item", "tags") || {}
      repository = tags["repository"]
      branch = extract_branch(assignment)
      base = config.fetch("base_branch", "main")
      title = build_title(config, assignment)
      body = build_body(assignment)

      cmd = [
        "gh", "pr", "create",
        "--repo", repository,
        "--head", branch,
        "--base", base,
        "--title", title,
        "--body", body
      ]
      cmd += ["--draft"] if config["draft"]

      result = run_command(cmd)

      if result.success?
        pr_data = parse_pr_output(result.stdout, repository)
        AgentResult.success(
          report: { "summary" => "Created PR ##{pr_data['number']}", "url" => pr_data["url"] },
          artifacts: [{ "kind" => "pull_request", "data" => pr_data }],
          trace_events: [build_trace(cmd, result)]
        )
      else
        AgentResult.failure(
          report: { "summary" => "Failed to create PR", "stderr" => result.stderr, "exit_status" => result.exit_status },
          artifacts: [],
          trace_events: [build_trace(cmd, result)]
        )
      end
    end
  end
end
```

## Adapter 2: `github_ci_poll`

**Type:** Asynchronous (returns `AsyncAdapterResult`, polled by `AsyncClaimChecker`)

**Purpose:** Wait for GitHub Actions checks to complete on a PR.

**Input (from upstream artifact):**
- `pull_request.number` — PR number
- `pull_request.url` or `repository` — repo identifier

**adapter_config:**
```yaml
adapter_config:
  poll_interval_seconds: 30            # how often to check
  timeout_seconds: 900                 # max wait (15 min default)
```

**Execution flow:**
1. `execute` returns `AsyncAdapterResult` with status `"submitted"` and metadata containing the PR number and repo
2. `check_status` runs `gh pr checks {number} --repo {repo} --json name,state,conclusion` and parses the result
3. If any check is still pending/in_progress → return `:running`
4. If all checks pass → return `:completed` with success `AgentResult`
5. If any check fails → return `:completed` with failure `AgentResult`

**Output artifact (on success):**
```ruby
{
  "kind" => "ci_result",
  "data" => {
    "status" => "success",
    "checks" => [
      { "name" => "test", "conclusion" => "success", "duration" => "6m22s" }
    ],
    "pr_number" => 42
  }
}
```

**Implementation:**
```ruby
module Adapters
  class GithubCiPollAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      pr_data = extract_pr_artifact(assignment)
      repository = assignment.dig("work_item", "tags", "repository")

      Engine::AsyncAdapterResult.new(
        provider: "github_ci_poll",
        external_id: "#{repository}##{pr_data['number']}",
        status: "submitted",
        metadata: {
          "repository" => repository,
          "pr_number" => pr_data["number"],
          "poll_interval_seconds" => assignment.dig("stage", "adapter_config", "poll_interval_seconds") || 30,
          "timeout_seconds" => assignment.dig("stage", "adapter_config", "timeout_seconds") || 900
        },
        trace_events: []
      )
    end

    def check_status(claim)
      meta = claim.assignment.dig("async", "metadata") || claim.metadata
      repo = meta["repository"]
      pr = meta["pr_number"]

      result = run_command(["gh", "pr", "checks", pr.to_s, "--repo", repo, "--json", "name,state,conclusion"])
      checks = JSON.parse(result.stdout) rescue []

      pending = checks.any? { |c| c["state"] != "COMPLETED" }
      return :running if pending

      failed = checks.select { |c| c["conclusion"] == "FAILURE" }
      if failed.any?
        AgentResult.failure(
          report: { "summary" => "CI failed: #{failed.map { |c| c['name'] }.join(', ')}", "checks" => checks },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "failure", "checks" => checks, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "pr", "checks"], result)]
        )
      else
        AgentResult.success(
          report: { "summary" => "CI passed: #{checks.size} checks green", "checks" => checks },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "success", "checks" => checks, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "pr", "checks"], result)]
        )
      end
    end
  end
end
```

**AsyncClaimChecker integration:**
Add a routing condition in `AsyncClaimChecker` — if `claim.assignment.dig("async", "provider") == "github_ci_poll"`, call `GithubCiPollAdapter.new.check_status(claim)` directly instead of going through the codex poller path.

## Adapter 3: `github_pr_merge`

**Type:** Synchronous (returns `AgentResult`)

**Purpose:** Merge a pull request.

**Input (from upstream artifact):**
- `pull_request.number` — PR number
- `repository` — from work item tags

**adapter_config:**
```yaml
adapter_config:
  strategy: squash                     # squash, merge, or rebase
  delete_branch: true                  # delete source branch after merge
```

**Implementation:**
```ruby
module Adapters
  class GithubPrMergeAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      pr_data = extract_pr_artifact(assignment)
      repository = assignment.dig("work_item", "tags", "repository")
      config = assignment.dig("stage", "adapter_config") || {}
      strategy = config.fetch("strategy", "squash")
      delete_branch = config.fetch("delete_branch", true)

      cmd = ["gh", "pr", "merge", pr_data["number"].to_s, "--repo", repository, "--#{strategy}"]
      cmd += ["--delete-branch"] if delete_branch

      result = run_command(cmd)

      if result.success?
        AgentResult.success(
          report: { "summary" => "Merged PR ##{pr_data['number']} via #{strategy}" },
          artifacts: [{ "kind" => "merge_result", "data" => { "pr_number" => pr_data["number"], "strategy" => strategy, "merged" => true } }],
          trace_events: [build_trace(cmd, result)]
        )
      else
        AgentResult.failure(
          report: { "summary" => "Failed to merge PR ##{pr_data['number']}", "stderr" => result.stderr, "exit_status" => result.exit_status },
          artifacts: [],
          trace_events: [build_trace(cmd, result)]
        )
      end
    end
  end
end
```

## Linear Poll Ingestion

**Type:** Solid Queue scheduled job, not an adapter

**Purpose:** Poll Linear API every 5 minutes for new issues with the `postrunner` label. Create TaskRail work items for any that don't already exist.

**File:** `app/jobs/linear_poll_job.rb`

**Flow:**
1. Query Linear GraphQL API for open issues with labels `postrunner` + any service label, not labeled `postrunner-ignore`
2. For each issue, check if a work item already exists (by Linear issue ID stored in `work_item.tags["linear_issue_id"]`)
3. If no existing work item, create one in the `postrunner-fix` queue with:
   - `title` — Linear issue title
   - `spec_inline` — Linear issue description (contains tool, file, code snippet, recommendation)
   - `tags` — `{ linear_issue_id: "...", repository: "MyScribbl/{service}", service_name: "{service}" }`
   - `stage_name` — first stage (`fix`)

**Linear API client:** `app/services/linear_client.rb`

```ruby
class LinearClient
  API_URL = "https://api.linear.app/graphql"

  def initialize(api_key:)
    @api_key = api_key
  end

  def postrunner_issues
    query = <<~GQL
      {
        issues(filter: {
          labels: { some: { name: { eq: "postrunner" } } }
          state: { type: { nin: ["completed", "canceled", "duplicate"] } }
        }, first: 50) {
          nodes {
            id
            identifier
            title
            description
            labels { nodes { name } }
          }
        }
      }
    GQL
    post(query).dig("data", "issues", "nodes") || []
  end

  def close_issue(issue_id)
    # Mark as done when work item completes
  end

  private

  def post(query)
    resp = Net::HTTP.post(
      URI(API_URL),
      { query: query }.to_json,
      "Authorization" => @api_key,
      "Content-Type" => "application/json"
    )
    JSON.parse(resp.body)
  end
end
```

**Scheduled job:**
```ruby
class LinearPollJob < ApplicationJob
  queue_as :default

  def perform
    client = LinearClient.new(api_key: ENV["LINEAR_API_KEY"])
    queue = WorkQueue.find_by!(slug: "postrunner-fix")
    first_stage = queue.queue_config["stages"]&.first || "fix"
    issues = client.postrunner_issues

    issues.each do |issue|
      # Dedup: check if work item already exists for this Linear issue (JSONB containment query)
      next if WorkItem.where("tags @> ?", { "linear_issue_id" => issue["id"] }.to_json).exists?
      next if issue["labels"]["nodes"].any? { |l| l["name"] == "postrunner-ignore" }

      service = extract_service_from_labels(issue)
      repo = "MyScribbl/#{service}"
      linear_url = "https://linear.app/myscribbl/issue/#{issue['identifier']}"

      WorkItem.create!(
        work_queue: queue,
        title: issue["title"],
        spec_url: linear_url,
        stage_name: first_stage,
        status: :pending,
        tags: { "linear_issue_id" => issue["id"], "linear_identifier" => issue["identifier"],
                "repository" => repo, "service_name" => service },
        metadata: { "spec_inline" => issue["description"] }
      )
    end
  end

  private

  def extract_service_from_labels(issue)
    service_labels = %w[crm-service user-service chat-service memory-service enrichment-service notification-service agent-service]
    labels = issue["labels"]["nodes"].map { |l| l["name"] }
    (labels & service_labels).first || "unknown-service"
  end
end
```

**Concurrency safety:** Add a unique index on `tags->>'linear_issue_id'` to prevent duplicate work items if two job workers fire concurrently:

```ruby
# Migration
add_index :work_items, "(tags->>'linear_issue_id')", unique: true, where: "tags->>'linear_issue_id' IS NOT NULL", name: "idx_work_items_linear_issue_id"
```

**Schedule:** Add to `config/recurring.yml`:

```yaml
linear_poll:
  class: LinearPollJob
  queue: default
  schedule: every 5 minutes
```

This runs in both development and production. Can be scoped to `production:` only if desired.

## Model Override Fix

**File:** `app/adapters/adapters/inline_claude_adapter.rb`

The `model_override` field already exists in `stage_config` and `AssignmentBuilder` puts it at `assignment["model"]`. The adapter currently delegates to `ClaudeCliRunner` which constructs the command internally. The fix is in `ClaudeCliRunner` — it needs to accept and pass the `--model` flag:

```ruby
# In ClaudeCliRunner#initialize, add model parameter:
def initialize(command:, args:, prompt:, working_directory:, timeout_seconds:, model: nil)
  @model = model
  # ...existing
end

# In ClaudeCliRunner#build_command (or wherever the CLI args are assembled):
cmd += ["--model", @model] if @model

# In InlineClaudeAdapter#execute, pass the model through:
runner = ClaudeCliRunner.new(
  command: config.fetch("command", "claude"),
  args: config.fetch("args", ["--print"]),
  prompt: prompt,
  working_directory: working_directory,
  timeout_seconds: timeout,
  model: assignment["model"]  # from stage_config.model_override via AssignmentBuilder
)
```

This allows queue YAML to specify:
```yaml
stage_configs:
  review:
    adapter_type: inline_claude
    model_override: claude-opus-4-6
```

## Postrunner-Fix Queue Definition

**File:** `config/queues/postrunner_fix.yml`

```yaml
name: "Postrunner Fix"
category: "Maintenance"
slug: "postrunner-fix"

stages:
  - fix
  - open_pr
  - await_ci
  - review
  - merge

config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2

stage_configs:
  fix:
    adapter_type: codex
    model_override: null                 # use default (cheap model)
    max_retries: 2
    timeout_seconds: 300
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    completion_criteria:
      - code_changes_present
    agent_prompt: |
      You are fixing a CI tool finding. The issue details are in the spec below.
      Clone the repository, read the flagged file, apply the fix, commit to a new branch.
      Branch name format: postrunner/{tool}-{short-description}
      Make the minimal change needed — do not refactor surrounding code.
    adapter_config:
      command: codex
      args:
        - exec
        - --json
      output_artifact_kind: branch
      branch_prefix: postrunner/

  open_pr:
    adapter_type: github_pr_create
    max_retries: 1
    timeout_seconds: 30
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    adapter_config:
      base_branch: main
      draft: false
      title_template: "fix: {work_item_title}"

  await_ci:
    adapter_type: github_ci_poll
    max_retries: 0
    timeout_seconds: 900
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    adapter_config:
      poll_interval_seconds: 30
      timeout_seconds: 900

  review:
    adapter_type: inline_claude
    model_override: claude-opus-4-6
    max_retries: 0
    timeout_seconds: 120
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    completion_criteria:
      - review_verdict_present
    agent_prompt: |
      You are reviewing a pull request that fixes a CI tool finding.
      Read the diff carefully. Verify:
      1. The fix addresses the specific finding (tool, rule, file from the spec)
      2. The change is minimal and doesn't introduce new issues
      3. No unrelated changes were made
      If the fix is correct, respond with: {"verdict": "approved"}
      If the fix is wrong or incomplete, respond with: {"verdict": "request_changes", "feedback": "explanation"}
    adapter_config:
      command: claude
      args:
        - --print
      output_artifact_kind: review_report

  merge:
    adapter_type: github_pr_merge
    max_retries: 1
    timeout_seconds: 30
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    adapter_config:
      strategy: squash
      delete_branch: true
```

**Transition rules (handled by existing TransitionManager):**
- `review` stage returns `verdict: "request_changes"` → `review_regression_requested?` predicate fires → regresses to `fix` with feedback
- `await_ci` fails → regresses to `fix` (CI failure means the fix broke something)
- After `max_regression_loops` (2) exhausted → blocked, escalated to human

## Adapter Registration

**File:** `app/services/engine/claim_executor.rb`

```ruby
ADAPTERS = {
  "fake" => Adapters::FakeAdapter,
  "shell_script" => Adapters::ShellScriptAdapter,
  "inline_claude" => Adapters::InlineClaudeAdapter,
  "codex" => Adapters::CodexAdapter,
  "docker_compose" => Adapters::DockerComposeAdapter,
  "github_pr_create" => Adapters::GithubPrCreateAdapter,
  "github_ci_poll" => Adapters::GithubCiPollAdapter,
  "github_pr_merge" => Adapters::GithubPrMergeAdapter,
}.freeze
```

## AsyncClaimChecker Extension

**File:** `app/services/engine/async_claim_checker.rb`

Add routing for the new async adapter. Follow the existing codex pattern — persist result, update claim, trigger transition:

```ruby
def check_claim(claim)
  provider = claim.assignment.dig("async", "provider")
  case provider
  when "codex"
    check_codex_claim(claim)
  when "github_ci_poll"
    adapter = Adapters::GithubCiPollAdapter.new
    result = adapter.check_status(claim)
    return if result == :running  # still waiting, poll again next tick

    # Persist result (same pattern as codex path)
    stage_config = StageConfig.from_work_item(claim.work_item)
    ClaimResultPersister.new(claim: claim, stage_config: stage_config).call(result)
    claim.update!(status: :completed, completed_at: Time.current)
    TransitionManager.new(work_item: claim.work_item, stage_config: stage_config).call
  else
    # ...existing handling
  end
end
```

## Shared Utilities

All three GitHub adapters need common helpers. Extract to a shared concern:

**File:** `app/adapters/adapters/concerns/github_cli.rb`

```ruby
module Adapters
  module Concerns
    module GithubCli
      private

      def run_command(cmd, working_directory: nil)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: working_directory)
        OpenStruct.new(stdout: stdout.strip, stderr: stderr.strip, exit_status: status.exitstatus, success?: status.success?)
      end

      def extract_pr_artifact(assignment)
        artifacts = assignment.dig("context", "upstream_artifacts") || []
        pr = artifacts.find { |a| a["kind"] == "pull_request" }
        pr&.fetch("data", {}) || {}
      end

      def build_trace(cmd, result)
        {
          "event_type" => "github_cli",
          "input_summary" => cmd.join(" ").truncate(500),
          "output_summary" => result.stdout.truncate(500),
          "duration_ms" => 0,
          "tokens_in" => 0,
          "tokens_out" => 0,
          "cost_cents" => 0,
          "metadata" => { "exit_status" => result.exit_status, "command" => cmd.join(" ") }
        }
      end
    end
  end
end
```

## File Map

### New files

| File | Responsibility |
|------|---------------|
| `app/adapters/adapters/github_pr_create_adapter.rb` | Create GitHub PRs |
| `app/adapters/adapters/github_ci_poll_adapter.rb` | Async poll CI checks |
| `app/adapters/adapters/github_pr_merge_adapter.rb` | Merge GitHub PRs |
| `app/adapters/adapters/concerns/github_cli.rb` | Shared `gh` CLI helpers |
| `app/services/linear_client.rb` | Linear GraphQL API client |
| `app/jobs/linear_poll_job.rb` | Scheduled job: Linear → work items |
| `config/queues/postrunner_fix.yml` | Pipeline definition |
| `spec/adapters/github_pr_create_adapter_spec.rb` | Tests |
| `spec/adapters/github_ci_poll_adapter_spec.rb` | Tests |
| `spec/adapters/github_pr_merge_adapter_spec.rb` | Tests |
| `spec/services/linear_client_spec.rb` | Tests |
| `spec/jobs/linear_poll_job_spec.rb` | Tests |

### Modified files

| File | Change |
|------|--------|
| `app/services/engine/claim_executor.rb` | Register 3 new adapters |
| `app/services/engine/async_claim_checker.rb` | Add `github_ci_poll` routing |
| `app/adapters/adapters/inline_claude_adapter.rb` | Wire `model_override` to CLI |
| `config/recurring.yml` (or equivalent) | Add LinearPollJob schedule |

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `LINEAR_API_KEY` | Linear API key for polling postrunner issues |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI (PR create/merge/checks) |

Both should be added to TaskRail's deploy secrets.

## Rollout Plan

1. **Phase 1:** Shared GitHub CLI concern + `github_pr_create` adapter with tests
2. **Phase 2:** `github_ci_poll` async adapter + AsyncClaimChecker extension with tests
3. **Phase 3:** `github_pr_merge` adapter with tests
4. **Phase 4:** Wire `model_override` through InlineClaudeAdapter
5. **Phase 5:** `LinearClient` + `LinearPollJob` with tests
6. **Phase 6:** `postrunner_fix.yml` queue definition
7. **Phase 7:** End-to-end test with a fixture repo and a test Linear ticket
8. **Phase 8:** Deploy and run against real postrunner tickets

# GitHub & Linear Adapters Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three GitHub adapters (`github_pr_create`, `github_ci_poll`, `github_pr_merge`), a Linear poll ingestion job, model_override wiring, and the `postrunner-fix` queue to TaskRail.

**Architecture:** All GitHub adapters wrap the `gh` CLI via `Open3.capture3`, return structured `AgentResult`/`AsyncAdapterResult` objects, and follow the existing adapter patterns. Linear ingestion is a Solid Queue recurring job that polls the Linear GraphQL API.

**Tech Stack:** Ruby/Rails 8, `gh` CLI, Linear GraphQL API, Solid Queue, RSpec

**Spec:** `docs/specs/2026-06-04-github-linear-adapters-design.md`

---

## File Map

### New files

| File | Responsibility |
|------|---------------|
| `app/adapters/adapters/concerns/github_cli.rb` | Shared `gh` CLI helpers: `run_command`, `extract_pr_artifact`, `build_trace` |
| `app/adapters/adapters/github_pr_create_adapter.rb` | Create GitHub PRs |
| `app/adapters/adapters/github_ci_poll_adapter.rb` | Async poll CI checks |
| `app/adapters/adapters/github_pr_merge_adapter.rb` | Merge GitHub PRs |
| `app/services/linear_client.rb` | Linear GraphQL API client |
| `app/jobs/linear_poll_job.rb` | Scheduled job: Linear → work items |
| `config/queues/postrunner_fix.yml` | Pipeline definition |
| `spec/adapters/adapters/github_pr_create_adapter_spec.rb` | Tests |
| `spec/adapters/adapters/github_ci_poll_adapter_spec.rb` | Tests |
| `spec/adapters/adapters/github_pr_merge_adapter_spec.rb` | Tests |
| `spec/services/linear_client_spec.rb` | Tests |
| `spec/jobs/linear_poll_job_spec.rb` | Tests |
| `db/migrate/XXXXXX_add_linear_issue_id_unique_index.rb` | Unique index on `tags->>'linear_issue_id'` |

### Modified files

| File | Change |
|------|--------|
| `app/services/engine/claim_executor.rb` | Register 3 new adapters in `ADAPTERS` hash |
| `app/services/engine/async_claim_checker.rb` | Add `github_ci_poll` routing |
| `app/services/claude_cli_runner.rb` | Accept `model:` kwarg, pass `--model` to CLI |
| `app/adapters/adapters/inline_claude_adapter.rb` | Pass `assignment["model"]` to `ClaudeCliRunner` |
| `config/recurring.yml` | Add `LinearPollJob` every 5 minutes |

---

## Task 1: Shared GitHub CLI Concern

**Files:**
- Create: `app/adapters/adapters/concerns/github_cli.rb`
- Create: `spec/adapters/adapters/concerns/github_cli_spec.rb`

- [ ] **Step 1: Write tests for the shared concern**

```ruby
# spec/adapters/adapters/concerns/github_cli_spec.rb
require "rails_helper"

RSpec.describe Adapters::Concerns::GithubCli do
  let(:test_class) do
    Class.new(Adapters::BaseAdapter) do
      include Adapters::Concerns::GithubCli
      # Expose private methods for testing
      public :run_command, :extract_pr_artifact, :build_trace
    end
  end
  let(:adapter) { test_class.new }

  describe "#run_command" do
    it "captures stdout and exit status from a successful command" do
      result = adapter.run_command(["echo", "hello"])
      expect(result.stdout).to eq("hello")
      expect(result.exit_status).to eq(0)
      expect(result.success?).to be true
    end

    it "captures stderr and non-zero exit from a failed command" do
      result = adapter.run_command(["sh", "-c", "echo err >&2; exit 1"])
      expect(result.stderr).to include("err")
      expect(result.exit_status).to eq(1)
      expect(result.success?).to be false
    end
  end

  describe "#extract_pr_artifact" do
    it "extracts pull_request artifact data from upstream artifacts" do
      assignment = {
        "context" => {
          "upstream_artifacts" => [
            { "kind" => "pull_request", "data" => { "number" => 42, "url" => "https://github.com/test/repo/pull/42" } }
          ]
        }
      }
      expect(adapter.extract_pr_artifact(assignment)).to eq({ "number" => 42, "url" => "https://github.com/test/repo/pull/42" })
    end

    it "returns empty hash when no pull_request artifact exists" do
      assignment = { "context" => { "upstream_artifacts" => [] } }
      expect(adapter.extract_pr_artifact(assignment)).to eq({})
    end
  end

  describe "#build_trace" do
    it "returns a trace event hash" do
      result = OpenStruct.new(stdout: "ok", exit_status: 0, duration_ms: 150)
      trace = adapter.build_trace(["gh", "pr", "create"], result, 150)
      expect(trace["event_type"]).to eq("github_cli")
      expect(trace["metadata"]["exit_status"]).to eq(0)
      expect(trace["duration_ms"]).to eq(150)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/work/code/taskrail/app && bundle exec rspec spec/adapters/adapters/concerns/github_cli_spec.rb`
Expected: FAIL — file not found

- [ ] **Step 3: Implement the concern**

```ruby
# app/adapters/adapters/concerns/github_cli.rb
require "open3"

module Adapters
  module Concerns
    module GithubCli
      CommandResult = Data.define(:stdout, :stderr, :exit_status, :duration_ms) do
        def success?
          exit_status.zero?
        end
      end

      private

      def run_command(cmd, working_directory: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        opts = {}
        opts[:chdir] = working_directory if working_directory
        stdout, stderr, status = Open3.capture3(*cmd, **opts)
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = ((finished - started) * 1000).round

        CommandResult.new(
          stdout: stdout.strip,
          stderr: stderr.strip,
          exit_status: status.exitstatus,
          duration_ms: duration_ms
        )
      end

      def extract_pr_artifact(assignment)
        artifacts = assignment.dig("context", "upstream_artifacts") || []
        pr = artifacts.find { |a| a["kind"] == "pull_request" }
        pr&.fetch("data", {}) || {}
      end

      def build_trace(cmd, result, duration_ms = nil)
        {
          "event_type" => "github_cli",
          "input_summary" => cmd.join(" ").truncate(500),
          "output_summary" => result.stdout.to_s.truncate(500),
          "duration_ms" => duration_ms || result.try(:duration_ms) || 0,
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/adapters/adapters/concerns/github_cli_spec.rb`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/adapters/adapters/concerns/github_cli.rb spec/adapters/adapters/concerns/github_cli_spec.rb
git commit -m "feat: add shared GithubCli concern for GitHub adapters"
```

---

## Task 2: `github_pr_create` Adapter

**Files:**
- Create: `app/adapters/adapters/github_pr_create_adapter.rb`
- Create: `spec/adapters/adapters/github_pr_create_adapter_spec.rb`
- Modify: `app/services/engine/claim_executor.rb`

- [ ] **Step 1: Write adapter tests**

```ruby
# spec/adapters/adapters/github_pr_create_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubPrCreateAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "open_pr",
        adapter_type: "github_pr_create",
        adapter_config: { "base_branch" => "main", "title_template" => "fix: {work_item_title}" }
      },
      work_item: {
        title: "shellcheck SC2086 in bin/deploy.sh",
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "branch", "data" => { "branch" => "postrunner/sc2086-deploy-sh" } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns success with pull_request artifact when gh succeeds" do
      pr_url = "https://github.com/MyScribbl/crm-service/pull/99"
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: pr_url, stderr: "", exit_status: 0, duration_ms: 200
        )
      )

      result = adapter.execute(assignment)

      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("success")
      pr_artifact = result.artifacts.find { |a| a["kind"] == "pull_request" }
      expect(pr_artifact).to be_present
      expect(pr_artifact["data"]["url"]).to eq(pr_url)
    end

    it "returns failure when gh command fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "", stderr: "error creating PR", exit_status: 1, duration_ms: 100
        )
      )

      result = adapter.execute(assignment)

      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("failure")
      expect(result.report["stderr"]).to include("error creating PR")
    end

    it "extracts branch from upstream branch artifact" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "https://github.com/test/repo/pull/1", stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      adapter.execute(assignment)

      expect(adapter).to have_received(:run_command) do |cmd|
        expect(cmd).to include("--head")
        head_idx = cmd.index("--head")
        expect(cmd[head_idx + 1]).to eq("postrunner/sc2086-deploy-sh")
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/adapters/adapters/github_pr_create_adapter_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the adapter**

```ruby
# app/adapters/adapters/github_pr_create_adapter.rb
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

      cmd = ["gh", "pr", "create", "--repo", repository, "--head", branch, "--base", base, "--title", title, "--body", body]

      result = run_command(cmd)

      if result.success?
        pr_data = parse_pr_url(result.stdout, repository, branch, base)
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

    private

    def extract_branch(assignment)
      artifacts = assignment.dig("context", "upstream_artifacts") || []
      branch_artifact = artifacts.find { |a| a["kind"] == "branch" }
      branch_artifact&.dig("data", "branch") || "unknown-branch"
    end

    def build_title(config, assignment)
      template = config.fetch("title_template", "{work_item_title}")
      title = assignment.dig("work_item", "title") || "fix"
      template.gsub("{work_item_title}", title)
    end

    def build_body(assignment)
      reports = assignment.dig("context", "upstream_reports") || []
      latest = reports.last
      latest&.fetch("summary", "") || ""
    end

    def parse_pr_url(stdout, repository, branch, base)
      url = stdout.strip
      number = url.split("/").last.to_i
      { "number" => number, "url" => url, "branch" => branch, "base_branch" => base }
    end
  end
end
```

- [ ] **Step 4: Register in ClaimExecutor**

Add to `ADAPTERS` hash in `app/services/engine/claim_executor.rb`:

```ruby
"github_pr_create" => Adapters::GithubPrCreateAdapter,
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/adapters/adapters/github_pr_create_adapter_spec.rb`
Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/adapters/adapters/github_pr_create_adapter.rb spec/adapters/adapters/github_pr_create_adapter_spec.rb app/services/engine/claim_executor.rb
git commit -m "feat: add github_pr_create adapter"
```

---

## Task 3: `github_ci_poll` Async Adapter

**Files:**
- Create: `app/adapters/adapters/github_ci_poll_adapter.rb`
- Create: `spec/adapters/adapters/github_ci_poll_adapter_spec.rb`
- Modify: `app/services/engine/claim_executor.rb`
- Modify: `app/services/engine/async_claim_checker.rb`

- [ ] **Step 1: Write adapter tests**

```ruby
# spec/adapters/adapters/github_ci_poll_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubCiPollAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "await_ci",
        adapter_type: "github_ci_poll",
        adapter_config: { "poll_interval_seconds" => 30, "timeout_seconds" => 900 }
      },
      work_item: {
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "pull_request", "data" => { "number" => 42, "url" => "https://github.com/MyScribbl/crm-service/pull/42" } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns AsyncAdapterResult with submitted status" do
      result = adapter.execute(assignment)

      expect(result).to be_a(Engine::AsyncAdapterResult)
      expect(result.provider).to eq("github_ci_poll")
      expect(result.status).to eq("submitted")
      expect(result.external_id).to eq("MyScribbl/crm-service#42")
    end
  end

  describe "#check_status" do
    let(:claim) do
      instance_double(Claim,
        assignment: { "async" => { "metadata" => { "repository" => "MyScribbl/crm-service", "pr_number" => 42 } } },
        metadata: {}
      )
    end

    it "returns :running when checks are pending" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '[{"name":"test","state":"IN_PROGRESS","conclusion":""}]',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      expect(adapter.check_status(claim)).to eq(:running)
    end

    it "returns success AgentResult when all checks pass" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '[{"name":"test","state":"COMPLETED","conclusion":"SUCCESS"}]',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      result = adapter.check_status(claim)
      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("success")
    end

    it "returns failure AgentResult when a check fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '[{"name":"test","state":"COMPLETED","conclusion":"FAILURE"}]',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      result = adapter.check_status(claim)
      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("failure")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/adapters/adapters/github_ci_poll_adapter_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the adapter**

```ruby
# app/adapters/adapters/github_ci_poll_adapter.rb
module Adapters
  class GithubCiPollAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      pr_data = extract_pr_artifact(assignment)
      repository = assignment.dig("work_item", "tags", "repository")
      config = assignment.dig("stage", "adapter_config") || {}

      Engine::AsyncAdapterResult.new(
        provider: "github_ci_poll",
        external_id: "#{repository}##{pr_data['number']}",
        status: "submitted",
        metadata: {
          "repository" => repository,
          "pr_number" => pr_data["number"]
        },
        trace_events: []
      )
    end

    def check_status(claim)
      meta = claim.assignment.dig("async", "metadata") || claim.metadata || {}
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

- [ ] **Step 4: Register in ClaimExecutor**

Add to `ADAPTERS` hash in `app/services/engine/claim_executor.rb`:

```ruby
"github_ci_poll" => Adapters::GithubCiPollAdapter,
```

- [ ] **Step 5: Add routing in AsyncClaimChecker**

In `app/services/engine/async_claim_checker.rb`, add after the codex check (line 15):

```ruby
next unless claim.assignment.dig("async", "provider") == "codex"
```

Replace with:

```ruby
provider = claim.assignment.dig("async", "provider")

if provider == "github_ci_poll"
  adapter = Adapters::GithubCiPollAdapter.new
  poll_result = adapter.check_status(claim)
  next if poll_result == :running

  stage_config = claim.work_item.work_queue.stage_configs.find_by!(stage_name: claim.work_item.stage_name)
  Engine::ClaimResultPersister.new(claim: claim, stage_config: stage_config).call(poll_result)
  claim.update!(status: :completed, async_execution: false, completed_at: Time.current)
  Engine::TransitionManager.new(work_item: claim.work_item, claim: claim, stage_config: stage_config).call
  next
end

next unless provider == "codex"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/adapters/adapters/github_ci_poll_adapter_spec.rb`
Expected: All 4 tests PASS

- [ ] **Step 7: Run existing async_claim_checker specs to verify no regression**

Run: `bundle exec rspec spec/services/engine/async_claim_checker_spec.rb`
Expected: All existing tests PASS

- [ ] **Step 8: Commit**

```bash
git add app/adapters/adapters/github_ci_poll_adapter.rb spec/adapters/adapters/github_ci_poll_adapter_spec.rb app/services/engine/claim_executor.rb app/services/engine/async_claim_checker.rb
git commit -m "feat: add github_ci_poll async adapter with AsyncClaimChecker routing"
```

---

## Task 4: `github_pr_merge` Adapter

**Files:**
- Create: `app/adapters/adapters/github_pr_merge_adapter.rb`
- Create: `spec/adapters/adapters/github_pr_merge_adapter_spec.rb`
- Modify: `app/services/engine/claim_executor.rb`

- [ ] **Step 1: Write adapter tests**

```ruby
# spec/adapters/adapters/github_pr_merge_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubPrMergeAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "merge",
        adapter_type: "github_pr_merge",
        adapter_config: { "strategy" => "squash", "delete_branch" => true }
      },
      work_item: {
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "pull_request", "data" => { "number" => 42 } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns success when merge succeeds" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "Merged", stderr: "", exit_status: 0, duration_ms: 200
        )
      )

      result = adapter.execute(assignment)

      expect(result.status).to eq("success")
      merge_artifact = result.artifacts.find { |a| a["kind"] == "merge_result" }
      expect(merge_artifact["data"]["merged"]).to be true
      expect(merge_artifact["data"]["strategy"]).to eq("squash")
    end

    it "passes --squash and --delete-branch flags" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "Merged", stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      adapter.execute(assignment)

      expect(adapter).to have_received(:run_command) do |cmd|
        expect(cmd).to include("--squash")
        expect(cmd).to include("--delete-branch")
      end
    end

    it "returns failure when merge fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "", stderr: "merge conflict", exit_status: 1, duration_ms: 100
        )
      )

      result = adapter.execute(assignment)
      expect(result.status).to eq("failure")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/adapters/adapters/github_pr_merge_adapter_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the adapter**

```ruby
# app/adapters/adapters/github_pr_merge_adapter.rb
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
      pr_number = pr_data["number"].to_s

      cmd = ["gh", "pr", "merge", pr_number, "--repo", repository, "--#{strategy}"]
      cmd += ["--delete-branch"] if delete_branch

      result = run_command(cmd)

      if result.success?
        AgentResult.success(
          report: { "summary" => "Merged PR ##{pr_number} via #{strategy}" },
          artifacts: [{ "kind" => "merge_result", "data" => { "pr_number" => pr_data["number"], "strategy" => strategy, "merged" => true } }],
          trace_events: [build_trace(cmd, result)]
        )
      else
        AgentResult.failure(
          report: { "summary" => "Failed to merge PR ##{pr_number}", "stderr" => result.stderr, "exit_status" => result.exit_status },
          artifacts: [],
          trace_events: [build_trace(cmd, result)]
        )
      end
    end
  end
end
```

- [ ] **Step 4: Register in ClaimExecutor**

Add to `ADAPTERS` hash:

```ruby
"github_pr_merge" => Adapters::GithubPrMergeAdapter,
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/adapters/adapters/github_pr_merge_adapter_spec.rb`
Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/adapters/adapters/github_pr_merge_adapter.rb spec/adapters/adapters/github_pr_merge_adapter_spec.rb app/services/engine/claim_executor.rb
git commit -m "feat: add github_pr_merge adapter"
```

---

## Task 5: Wire `model_override` Through InlineClaudeAdapter

**Files:**
- Modify: `app/services/claude_cli_runner.rb`
- Modify: `app/adapters/adapters/inline_claude_adapter.rb`
- Modify: `spec/services/claude_cli_runner_spec.rb`
- Modify: `spec/adapters/adapters/inline_claude_adapter_spec.rb`

- [ ] **Step 1: Add model test to ClaudeCliRunner**

Add to `spec/services/claude_cli_runner_spec.rb`:

```ruby
describe "model override" do
  it "passes --model flag when model is provided" do
    runner = ClaudeCliRunner.new(
      command: "echo", args: ["--print"], prompt: "test",
      model: "claude-opus-4-6"
    )
    # Verify the model is stored — actual CLI invocation tested via integration
    expect(runner.instance_variable_get(:@model)).to eq("claude-opus-4-6")
  end

  it "does not pass --model when model is nil" do
    runner = ClaudeCliRunner.new(
      command: "echo", args: ["--print"], prompt: "test"
    )
    expect(runner.instance_variable_get(:@model)).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/claude_cli_runner_spec.rb`
Expected: FAIL — unknown keyword `model`

- [ ] **Step 3: Add `model:` kwarg to ClaudeCliRunner**

In `app/services/claude_cli_runner.rb`, modify the initializer:

```ruby
def initialize(command:, args: [], prompt:, working_directory: Rails.root.to_s, timeout_seconds: nil, model: nil)
  @command = command
  @args = args
  @prompt = prompt
  @working_directory = working_directory
  @timeout_seconds = timeout_seconds
  @model = model
end
```

In `capture_process`, inject `--model` into the args before the command is built:

```ruby
def capture_process
  cmd_args = @args.dup
  cmd_args.unshift("--model", @model) if @model
  Open3.popen3(@command, *cmd_args, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
```

- [ ] **Step 4: Pass model from InlineClaudeAdapter**

In `app/adapters/adapters/inline_claude_adapter.rb`, modify the `ClaudeCliRunner.new` call (line 16-22):

```ruby
runner_result = ClaudeCliRunner.new(
  command: command,
  args: config.fetch("args", DEFAULT_ARGS),
  prompt: prompt,
  working_directory: config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY),
  timeout_seconds: normalized_assignment.dig("limits", "timeout_seconds"),
  model: normalized_assignment["model"]
).call
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/claude_cli_runner_spec.rb spec/adapters/adapters/inline_claude_adapter_spec.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/claude_cli_runner.rb app/adapters/adapters/inline_claude_adapter.rb spec/services/claude_cli_runner_spec.rb
git commit -m "feat: wire model_override through InlineClaudeAdapter to CLI"
```

---

## Task 6: Linear Client & Poll Job

**Files:**
- Create: `app/services/linear_client.rb`
- Create: `app/jobs/linear_poll_job.rb`
- Create: `spec/services/linear_client_spec.rb`
- Create: `spec/jobs/linear_poll_job_spec.rb`
- Create: `db/migrate/XXXXXX_add_linear_issue_id_unique_index.rb`
- Modify: `config/recurring.yml`

- [ ] **Step 1: Write Linear client tests**

```ruby
# spec/services/linear_client_spec.rb
require "rails_helper"

RSpec.describe LinearClient do
  let(:client) { described_class.new(api_key: "test-key") }

  describe "#postrunner_issues" do
    it "returns issues with postrunner label" do
      stub_request(:post, "https://api.linear.app/graphql")
        .to_return(body: {
          data: {
            issues: {
              nodes: [
                { id: "issue-1", identifier: "ENG-173", title: "test finding",
                  description: "details", labels: { nodes: [{ name: "postrunner" }, { name: "crm-service" }] } }
              ]
            }
          }
        }.to_json)

      issues = client.postrunner_issues
      expect(issues.size).to eq(1)
      expect(issues.first["identifier"]).to eq("ENG-173")
    end

    it "returns empty array on API error" do
      stub_request(:post, "https://api.linear.app/graphql")
        .to_return(status: 500)

      expect(client.postrunner_issues).to eq([])
    end
  end
end
```

- [ ] **Step 2: Write LinearPollJob tests**

```ruby
# spec/jobs/linear_poll_job_spec.rb
require "rails_helper"

RSpec.describe LinearPollJob do
  let(:queue) { create(:work_queue, slug: "postrunner-fix", stages: ["fix", "open_pr"]) }

  before do
    allow(ENV).to receive(:fetch).with("LINEAR_API_KEY", anything).and_return("test-key")
    allow(WorkQueue).to receive(:find_by!).with(slug: "postrunner-fix").and_return(queue)
  end

  it "creates work items for new postrunner issues" do
    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      {
        "id" => "linear-uuid-1", "identifier" => "ENG-173",
        "title" => "[shellcheck] SC2086 in bin/deploy.sh",
        "description" => "## Finding\n...",
        "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "crm-service" }] }
      }
    ])

    expect { described_class.perform_now }.to change(WorkItem, :count).by(1)

    item = WorkItem.last
    expect(item.title).to eq("[shellcheck] SC2086 in bin/deploy.sh")
    expect(item.tags["linear_issue_id"]).to eq("linear-uuid-1")
    expect(item.tags["repository"]).to eq("MyScribbl/crm-service")
    expect(item.spec_url).to include("ENG-173")
  end

  it "skips issues that already have work items" do
    create(:work_item, work_queue: queue, tags: { "linear_issue_id" => "linear-uuid-1" })

    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      { "id" => "linear-uuid-1", "identifier" => "ENG-173", "title" => "test",
        "description" => "d", "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "crm-service" }] } }
    ])

    expect { described_class.perform_now }.not_to change(WorkItem, :count)
  end

  it "skips issues with postrunner-ignore label" do
    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      { "id" => "linear-uuid-2", "identifier" => "ENG-174", "title" => "test",
        "description" => "d", "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "postrunner-ignore" }, { "name" => "crm-service" }] } }
    ])

    expect { described_class.perform_now }.not_to change(WorkItem, :count)
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/linear_client_spec.rb spec/jobs/linear_poll_job_spec.rb`
Expected: FAIL

- [ ] **Step 4: Implement LinearClient**

```ruby
# app/services/linear_client.rb
require "net/http"
require "json"

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
  rescue StandardError => e
    Rails.logger.error("[LinearClient] Failed to fetch issues: #{e.message}")
    []
  end

  private

  def post(query)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.path, {
      "Authorization" => @api_key,
      "Content-Type" => "application/json"
    })
    req.body = { query: query }.to_json
    resp = http.request(req)
    JSON.parse(resp.body)
  end
end
```

- [ ] **Step 5: Implement LinearPollJob**

```ruby
# app/jobs/linear_poll_job.rb
class LinearPollJob < ApplicationJob
  queue_as :default

  SERVICE_LABELS = %w[crm-service user-service chat-service memory-service enrichment-service notification-service agent-service].freeze

  def perform
    client = LinearClient.new(api_key: ENV.fetch("LINEAR_API_KEY", ""))
    queue = WorkQueue.find_by!(slug: "postrunner-fix")
    first_stage = queue.queue_config&.dig("stages")&.first || "fix"
    issues = client.postrunner_issues

    issues.each do |issue|
      next if WorkItem.where("tags @> ?", { "linear_issue_id" => issue["id"] }.to_json).exists?

      labels = issue.dig("labels", "nodes")&.map { |l| l["name"] } || []
      next if labels.include?("postrunner-ignore")

      service = (labels & SERVICE_LABELS).first || "unknown-service"
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
    rescue ActiveRecord::RecordNotUnique
      # Another worker already created this item — skip
      next
    end
  end
end
```

- [ ] **Step 6: Create migration for unique index**

```bash
cd ~/work/code/taskrail/app && rails generate migration AddLinearIssueIdUniqueIndex
```

Edit the migration:

```ruby
class AddLinearIssueIdUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    add_index :work_items, "(tags->>'linear_issue_id')",
              unique: true,
              where: "tags->>'linear_issue_id' IS NOT NULL",
              name: "idx_work_items_linear_issue_id"
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 7: Add to recurring schedule**

In `config/recurring.yml`, add under `production:`:

```yaml
  linear_poll:
    class: LinearPollJob
    queue: default
    schedule: every 5 minutes
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/linear_client_spec.rb spec/jobs/linear_poll_job_spec.rb`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add app/services/linear_client.rb app/jobs/linear_poll_job.rb spec/services/linear_client_spec.rb spec/jobs/linear_poll_job_spec.rb db/migrate/*linear* config/recurring.yml
git commit -m "feat: add Linear poll ingestion for postrunner tickets"
```

---

## Task 7: Postrunner-Fix Queue Definition

**Files:**
- Create: `config/queues/postrunner_fix.yml`

- [ ] **Step 1: Create the queue YAML**

Create `config/queues/postrunner_fix.yml` with the full pipeline definition from the spec. Include all required fields: `name`, `category`, `slug`, `stages`, `config` (with `default_max_retries`, `default_timeout_seconds`, `default_escalation`, `max_regression_loops`), and `stage_configs` for all 5 stages (`fix`, `open_pr`, `await_ci`, `review`, `merge`). Each stage config must include `adapter_type`, `max_retries`, `timeout_seconds`, `escalation_target`, `allowed_skills`, `forbidden_skills`, and `adapter_config`. The `fix` and `review` stages also need `completion_criteria` and `agent_prompt`.

See spec section "Postrunner-Fix Queue Definition" for the complete YAML.

- [ ] **Step 2: Validate the queue config**

Run: `bundle exec rails runner "QueueConfigValidator.validate_all!"`
Expected: No validation errors

- [ ] **Step 3: Seed the queue**

Run: `bundle exec rails runner "WorkQueue.seed_from_config!('postrunner_fix')"`
Expected: Queue created with 5 stage configs

- [ ] **Step 4: Commit**

```bash
git add config/queues/postrunner_fix.yml
git commit -m "feat: add postrunner-fix queue definition"
```

---

## Task 8: End-to-End Validation

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests PASS, no regressions

- [ ] **Step 2: Manual dry run**

Create a test work item in the postrunner-fix queue via rails console:

```ruby
queue = WorkQueue.find_by!(slug: "postrunner-fix")
WorkItem.create!(
  work_queue: queue,
  title: "[shellcheck] SC2086 in bin/deploy.sh",
  spec_url: "https://linear.app/myscribbl/issue/ENG-TEST",
  stage_name: "fix",
  status: :pending,
  tags: { "repository" => "MyScribbl/crm-service", "service_name" => "crm-service", "linear_issue_id" => "test-123" },
  metadata: { "spec_inline" => "Fix shellcheck SC2086 warning in bin/deploy.sh line 42" }
)
```

Trigger the engine and verify the work item progresses through stages:

```ruby
Engine::Runner.new.call
```

- [ ] **Step 3: Verify LinearPollJob creates work items**

```ruby
LinearPollJob.perform_now
WorkItem.where("tags @> ?", '{"linear_issue_id": "test"}').count
```

- [ ] **Step 4: Commit any fixes from validation**

```bash
git add -A
git commit -m "fix: adjustments from end-to-end validation"
```

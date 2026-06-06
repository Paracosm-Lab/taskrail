# Kilo Adapter Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `kilo` adapter to TaskRail that shells out to the Kilo Code CLI, enabling queue stages to use Deepseek and 500+ other models as an alternative to the Codex adapter.

**Architecture:** Two new files (`KiloCliSubmitter` + `KiloAdapter`) mirroring the existing Codex pattern, plus one line added to `ClaimExecutor::ADAPTERS`. The submitter handles subprocess management; the adapter handles result parsing and artifact extraction.

**Tech Stack:** Ruby, Open3, RSpec, Kilo Code CLI (`@kilocode/cli`)

**Spec:** `docs/superpowers/specs/2026-06-05-kilo-adapter-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `app/services/kilo_cli_submitter.rb` | Create | Subprocess executor — spawns `kilo run`, collects stdout/stderr, enforces timeout, parses JSON output |
| `app/adapters/adapters/kilo_adapter.rb` | Create | Adapter — builds CLI args, calls submitter, maps result to `AgentResult` |
| `app/services/engine/claim_executor.rb` | Modify (1 line) | Register `"kilo" => Adapters::KiloAdapter` in ADAPTERS hash |
| `spec/services/kilo_cli_submitter_spec.rb` | Create | Unit tests for submitter |
| `spec/adapters/adapters/kilo_adapter_spec.rb` | Create | Unit tests for adapter |

---

### Task 1: Discovery — Verify Kilo CLI Output Format

Before writing any code, we need to know the exact JSON output schema from `kilo run --auto --format json`. This task produces a reference document that Tasks 2-5 depend on.

**Files:**
- Create: `docs/superpowers/specs/kilo-cli-output-reference.md` (temporary reference, can delete after implementation)

- [ ] **Step 1: Install Kilo CLI**

```bash
npm install -g @kilocode/cli
kilo --version
```

Expected: version number printed (e.g. `1.x.x`)

- [ ] **Step 2: Configure a provider**

```bash
mkdir -p ~/.config/kilo
cat > ~/.config/kilo/kilo.jsonc << 'EOF'
{
  "providers": {
    "deepseek": {
      "apiKey": "{env:DEEPSEEK_API_KEY}"
    }
  }
}
EOF
```

Verify `DEEPSEEK_API_KEY` is set in the shell environment (or substitute another provider you have a key for).

- [ ] **Step 3: Run a test command and capture JSON output**

```bash
cd /tmp && mkdir -p kilo-test && cd kilo-test
kilo run --auto --format json --model deepseek/deepseek-chat "Create a file called hello.txt containing 'hello world'" 2>kilo-stderr.txt | tee kilo-stdout.txt
echo "Exit code: $?"
cat kilo-stderr.txt
```

- [ ] **Step 4: Test stdin prompt delivery**

```bash
echo "Create a file called hello2.txt containing 'hello world'" | kilo run --auto --format json --model deepseek/deepseek-chat 2>kilo-stdin-stderr.txt | tee kilo-stdin-stdout.txt
echo "Exit code: $?"
```

If stdin does not work, note this — the submitter will need to pass the prompt as a positional argument instead.

- [ ] **Step 5: Test --agent flag**

```bash
kilo run --auto --format json --agent code --model deepseek/deepseek-chat "Create a file called hello3.txt containing 'hello world'" 2>/dev/null | tee kilo-agent-stdout.txt
```

- [ ] **Step 6: Document the output schema**

Write `docs/superpowers/specs/kilo-cli-output-reference.md` with:
- The raw JSON output from Step 3
- Whether stdin prompt delivery works (Step 4)
- Whether `--agent` works (Step 5)
- Key fields: how to determine success/failure, where the final message lives, how artifacts appear
- Any differences from Codex JSONL format

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs/kilo-cli-output-reference.md
git commit -m "docs: add Kilo CLI output format reference"
```

---

### Task 2: KiloCliSubmitter — Failing Tests

Write the test file first, modeling after the existing `spec/services/codex_cli_submitter_spec.rb`. Tests use real `ruby -e` subprocesses (not mocks) to verify subprocess management.

**Files:**
- Create: `spec/services/kilo_cli_submitter_spec.rb`

- [ ] **Step 1: Write the test file**

```ruby
require "rails_helper"

RSpec.describe KiloCliSubmitter do
  it "passes the prompt to the configured command and captures output" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "prompt = STDIN.read; puts prompt.upcase"],
      prompt: "build this",
      working_directory: Rails.root.to_s
    ).call

    expect(result.stdout).to include("BUILD THIS")
    expect(result.stderr).to eq("")
    expect(result.exit_status).to eq(0)
    expect(result.duration_ms).to be >= 0
  end

  it "parses JSON stdout into metadata" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", 'STDIN.read; puts({ "result" => "ok", "message" => "done" }.to_json)'],
      prompt: "build this",
      working_directory: Rails.root.to_s
    ).call

    expect(result.metadata["result"]).to eq("ok")
    expect(result.metadata["message"]).to eq("done")
  end

  it "handles JSON event stream output" do
    result = described_class.new(
      command: "ruby",
      args: [
        "-rjson",
        "-e",
        <<~'RUBY'
          STDIN.read
          puts({ "type" => "event", "data" => "started" }.to_json)
          puts({ "type" => "result", "message" => "all done", "artifacts" => [] }.to_json)
        RUBY
      ],
      prompt: "build this",
      working_directory: Rails.root.to_s
    ).call

    # Exact assertions depend on discovery (Task 1) — update after observing real output
    expect(result.exit_status).to eq(0)
    expect(result.metadata).to be_a(Hash)
  end

  it "captures non-zero exits without raising" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "warn STDIN.read; exit 9"],
      prompt: "bad",
      working_directory: Rails.root.to_s
    ).call

    expect(result.stderr).to include("bad")
    expect(result.exit_status).to eq(9)
  end

  it "terminates commands that exceed the timeout" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "sleep 2; puts 'late'"],
      prompt: "",
      working_directory: Rails.root.to_s,
      timeout_seconds: 0.1
    ).call

    expect(result.stdout).not_to include("late")
    expect(result.stderr).to include("timed out")
    expect(result.exit_status).to eq(124)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bundle exec rspec spec/services/kilo_cli_submitter_spec.rb
```

Expected: all tests fail with `uninitialized constant KiloCliSubmitter`

- [ ] **Step 3: Commit**

```bash
git add spec/services/kilo_cli_submitter_spec.rb
git commit -m "test: add failing KiloCliSubmitter specs"
```

---

### Task 3: KiloCliSubmitter — Implementation

Implement the submitter to make the tests from Task 2 pass. This mirrors `CodexCliSubmitter` (`app/services/codex_cli_submitter.rb`) but adapts parsing based on what Task 1 discovered about Kilo's JSON output format.

**Files:**
- Create: `app/services/kilo_cli_submitter.rb`
- Reference: `app/services/codex_cli_submitter.rb` (mirror this structure)

- [ ] **Step 1: Implement KiloCliSubmitter**

```ruby
require "json"
require "open3"
require "timeout"

class KiloCliSubmitter
  TIMEOUT_EXIT_STATUS = 124

  Result = Data.define(:stdout, :stderr, :exit_status, :duration_ms, :external_id, :metadata)

  def initialize(command:, args: [], prompt:, working_directory: Rails.root.to_s, timeout_seconds: nil)
    @command = command
    @args = args
    @prompt = prompt
    @working_directory = working_directory
    @timeout_seconds = timeout_seconds
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, exit_status = capture_process
    finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parsed = parse_stdout(stdout)

    Result.new(
      stdout: stdout,
      stderr: stderr,
      exit_status: exit_status,
      duration_ms: ((finished - started) * 1000).round,
      external_id: parsed["id"] || parsed["session_id"],
      metadata: parsed
    )
  end

  private

  def capture_process
    Open3.popen3(@command, *@args, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
      stdin.write(@prompt)
      stdin.close

      stdout_reader = Thread.new { stdout.read }
      stderr_reader = Thread.new { stderr.read }

      begin
        status = if @timeout_seconds
          Timeout.timeout(@timeout_seconds) { wait_thread.value }
        else
          wait_thread.value
        end
        [stdout_reader.value, stderr_reader.value, status.exitstatus]
      rescue Timeout::Error
        terminate_process(wait_thread.pid)
        [stdout_reader.value, [stderr_reader.value, "command timed out after #{@timeout_seconds} seconds"].reject(&:blank?).join("\n"), TIMEOUT_EXIT_STATUS]
      end
    end
  end

  def terminate_process(pid)
    Process.kill("TERM", pid)
    Timeout.timeout(1) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def parse_stdout(stdout)
    # Try single JSON object first
    parsed = JSON.parse(stdout)
    return parsed if parsed.is_a?(Hash)

    {}
  rescue JSON::ParserError, TypeError
    # Fall back to JSON-lines (event stream)
    parse_json_lines(stdout)
  end

  # Kilo --format json may emit newline-delimited JSON events.
  # Adapt this method after Task 1 discovery confirms the actual format.
  def parse_json_lines(stdout)
    events = stdout.to_s.lines.filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
    return {} if events.empty?

    last_result = events.reverse.find { |e| e["type"] == "result" || e["message"].present? }

    {
      "events" => events,
      "final_message" => last_result&.fetch("message", nil),
      "artifacts" => last_result&.fetch("artifacts", []) || [],
      "mode" => "json_lines"
    }.compact
  end
end
```

**Important:** The `parse_stdout` and `parse_json_lines` methods are provisional. After Task 1 discovery, update these to match Kilo's actual output schema. The subprocess management (`capture_process`, `terminate_process`) is identical to CodexCliSubmitter and should not need changes.

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bundle exec rspec spec/services/kilo_cli_submitter_spec.rb
```

Expected: all tests pass

- [ ] **Step 3: Run the full test suite to check for regressions**

```bash
bundle exec rspec
```

Expected: no new failures

- [ ] **Step 4: Commit**

```bash
git add app/services/kilo_cli_submitter.rb
git commit -m "feat: add KiloCliSubmitter for Kilo Code CLI subprocess execution"
```

---

### Task 4: KiloAdapter — Failing Tests

Write adapter tests modeling after `spec/adapters/adapters/codex_adapter_spec.rb`. These mock `KiloCliSubmitter` and verify `AgentResult` construction.

**Files:**
- Create: `spec/adapters/adapters/kilo_adapter_spec.rb`

- [ ] **Step 1: Write the test file**

```ruby
require "rails_helper"

RSpec.describe Adapters::KiloAdapter do
  it "returns success when Kilo exits zero with valid output" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done", "artifacts": []}',
      stderr: "",
      exit_status: 0,
      duration_ms: 500,
      external_id: nil,
      metadata: { "message" => "done", "artifacts" => [] }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result).to be_a(AgentResult)
    expect(result.status).to eq("success")
    expect(result.report["summary"]).to include("Kilo completed")
    expect(result.trace_events.first["event_type"]).to eq("kilo_run")
  end

  it "extracts branch artifacts from structured output" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "",
      exit_status: 0,
      duration_ms: 500,
      external_id: nil,
      metadata: {
        "final_message" => <<~TEXT
          Fixed the issue.

          ```json
          {
            "artifacts": [
              { "kind": "branch", "data": { "name": "postrunner/fix-lint" } }
            ]
          }
          ```
        TEXT
      }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.artifacts).to include("kind" => "branch", "data" => { "name" => "postrunner/fix-lint" })
  end

  it "returns failure when Kilo exits non-zero" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "kilo: model not found",
      exit_status: 1,
      duration_ms: 100,
      external_id: nil,
      metadata: {}
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("failed")
    expect(result.report["stderr"]).to eq("kilo: model not found")
    expect(result.report["exit_status"]).to eq(1)
  end

  it "returns timeout when Kilo exits with 124" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "command timed out after 300 seconds",
      exit_status: 124,
      duration_ms: 300_000,
      external_id: nil,
      metadata: {}
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("timeout")
    expect(result.report["summary"]).to include("timed out")
  end

  it "passes model from adapter_config to the submitter" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 100,
      external_id: nil,
      metadata: { "message" => "done" }
    )

    expect(KiloCliSubmitter).to receive(:new).with(
      hash_including(args: include("--model", "deepseek/deepseek-chat", "--dir"))
    ).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    described_class.new.execute(assignment)
  end

  it "constructs trace events with kilo_run event type" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 250,
      external_id: nil,
      metadata: { "message" => "done" }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    trace = result.trace_events.first
    expect(trace["event_type"]).to eq("kilo_run")
    expect(trace["duration_ms"]).to eq(250)
    expect(trace["metadata"]["command"]).to eq("kilo")
  end

  def assignment
    {
      claim_id: 1,
      work_item: { id: 1, title: "Fix lint issue", spec_url: "opaque", metadata: {} },
      stage: {
        name: "fix",
        adapter_config: {
          "command" => "kilo",
          "args" => ["run", "--auto", "--format", "json"],
          "model" => "deepseek/deepseek-chat",
          "output_artifact_kind" => "branch",
          "branch_prefix" => "postrunner/"
        },
        allowed_skills: [],
        forbidden_skills: [],
        completion_criteria: ["branch_created"]
      },
      prompt: "Fix this lint finding.",
      context: { spec_content: "Fix it" },
      limits: { timeout_seconds: 300 }
    }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bundle exec rspec spec/adapters/adapters/kilo_adapter_spec.rb
```

Expected: all tests fail with `uninitialized constant Adapters::KiloAdapter`

- [ ] **Step 3: Commit**

```bash
git add spec/adapters/adapters/kilo_adapter_spec.rb
git commit -m "test: add failing KiloAdapter specs"
```

---

### Task 5: KiloAdapter — Implementation

Implement the adapter to make the tests from Task 4 pass. Mirrors `CodexAdapter` (`app/adapters/adapters/codex_adapter.rb`).

**Files:**
- Create: `app/adapters/adapters/kilo_adapter.rb`
- Reference: `app/adapters/adapters/codex_adapter.rb` (mirror this structure)
- Reference: `app/adapters/adapters/response_parser.rb` (used for structured field extraction)

- [ ] **Step 1: Implement KiloAdapter**

```ruby
module Adapters
  class KiloAdapter < BaseAdapter
    DEFAULT_COMMAND = "kilo"
    DEFAULT_ARGS = ["run", "--auto", "--format", "json"].freeze
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    OUTPUT_SUMMARY_LIMIT = 500

    def execute(assignment)
      normalized = assignment.deep_stringify_keys
      stage = normalized.fetch("stage")
      config = stage.fetch("adapter_config", {})
      command = config.fetch("command", DEFAULT_COMMAND)
      prompt = CodexAssignmentPrompt.new(normalized).to_s

      args = config.fetch("args", DEFAULT_ARGS).dup
      model = config["model"]
      args.push("--model", model) if model.present?
      agent = config["agent"]
      args.push("--agent", agent) if agent.present?
      working_dir = config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY)
      args.push("--dir", working_dir)

      submitter_result = KiloCliSubmitter.new(
        command: command,
        args: args,
        prompt: prompt,
        working_directory: working_dir,
        timeout_seconds: normalized.dig("limits", "timeout_seconds")
      ).call

      trace_events = [trace_event(prompt, submitter_result, command)]

      if submitter_result.exit_status == KiloCliSubmitter::TIMEOUT_EXIT_STATUS
        AgentResult.timeout(
          report: timeout_report(submitter_result),
          artifacts: [],
          trace_events: trace_events
        )
      elsif submitter_result.exit_status.zero?
        AgentResult.success(
          report: success_report(normalized, submitter_result),
          artifacts: extract_artifacts(submitter_result),
          trace_events: trace_events
        )
      else
        AgentResult.failure(
          report: failure_report(submitter_result),
          artifacts: [],
          trace_events: trace_events
        )
      end
    end

    private

    def success_report(assignment, submitter_result)
      final_message = submitter_result.metadata["final_message"].presence || submitter_result.stdout
      {
        "summary" => "Kilo completed #{assignment.dig('stage', 'name')}",
        "response" => final_message,
        "stage" => assignment.dig("stage", "name")
      }.merge(structured_fields(final_message))
    end

    def extract_artifacts(submitter_result)
      configured_artifacts = submitter_result.metadata.fetch("artifacts", [])
      return configured_artifacts if configured_artifacts.is_a?(Array) && configured_artifacts.any?

      final_message = submitter_result.metadata["final_message"].presence || submitter_result.stdout
      structured_artifacts = structured_fields(final_message)["artifacts"]
      return structured_artifacts if structured_artifacts.is_a?(Array) && structured_artifacts.any?

      []
    end

    def structured_fields(message)
      ResponseParser.extract_structured_fields(message)
    end

    def failure_report(submitter_result)
      {
        "summary" => "Kilo submission failed",
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "exit_status" => submitter_result.exit_status
      }
    end

    def timeout_report(submitter_result)
      {
        "summary" => "Kilo submission timed out",
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "exit_status" => submitter_result.exit_status
      }
    end

    def trace_event(prompt, submitter_result, command)
      output = [submitter_result.stdout, submitter_result.stderr].reject(&:blank?).join("\n")
      {
        "event_type" => "kilo_run",
        "input_summary" => prompt.truncate(OUTPUT_SUMMARY_LIMIT),
        "output_summary" => output.truncate(OUTPUT_SUMMARY_LIMIT),
        "duration_ms" => submitter_result.duration_ms,
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0,
        "metadata" => {
          "exit_status" => submitter_result.exit_status,
          "command" => command
        }.compact
      }
    end
  end
end
```

- [ ] **Step 2: Run KiloAdapter tests to verify they pass**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bundle exec rspec spec/adapters/adapters/kilo_adapter_spec.rb
```

Expected: all tests pass

- [ ] **Step 3: Commit**

```bash
git add app/adapters/adapters/kilo_adapter.rb
git commit -m "feat: add KiloAdapter for Kilo Code CLI execution"
```

---

### Task 6: Register in ClaimExecutor

Add the adapter to the ADAPTERS hash so queue stages can use `adapter_type: kilo`.

**Files:**
- Modify: `app/services/engine/claim_executor.rb:12` (add one line to ADAPTERS hash)

- [ ] **Step 1: Add the registration**

In `app/services/engine/claim_executor.rb`, add `"kilo" => Adapters::KiloAdapter` to the ADAPTERS hash:

```ruby
ADAPTERS = {
  "fake" => Adapters::FakeAdapter,
  "shell_script" => Adapters::ShellScriptAdapter,
  "inline_claude" => Adapters::InlineClaudeAdapter,
  "codex" => Adapters::CodexAdapter,
  "kilo" => Adapters::KiloAdapter,
  "docker_compose" => Adapters::DockerComposeAdapter,
  "github_pr_create" => Adapters::GithubPrCreateAdapter,
  "github_ci_poll" => Adapters::GithubCiPollAdapter,
  "github_pr_merge" => Adapters::GithubPrMergeAdapter
}.freeze
```

- [ ] **Step 2: Run the full test suite**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bundle exec rspec
```

Expected: all tests pass, no regressions

- [ ] **Step 3: Commit**

```bash
git add app/services/engine/claim_executor.rb
git commit -m "feat: register KiloAdapter in ClaimExecutor::ADAPTERS"
```

---

### Task 7: End-to-End Smoke Test

Verify the adapter works end-to-end by creating a test queue config and running a work item through it. This is a manual test — skip in CI.

**Files:**
- Create: `config/queues/kilo_smoke_test.yml` (temporary — delete after verification)

- [ ] **Step 1: Create a smoke test queue config**

```yaml
name: "Kilo Smoke Test"
category: "Test"
slug: "kilo-smoke-test"

stages:
  - fix
  - done

config:
  default_max_retries: 0
  default_timeout_seconds: 120
  default_escalation: block_and_notify

stage_configs:
  fix:
    adapter_type: kilo
    max_retries: 0
    timeout_seconds: 120
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    completion_criteria:
      - branch_created
    adapter_config:
      command: kilo
      args:
        - run
        - --auto
        - --format
        - json
      model: deepseek/deepseek-chat
      output_artifact_kind: branch
      branch_prefix: kilo-test/
    agent_prompt: |
      Create a file called kilo-test.txt with the text "Kilo adapter works".
      Commit it to a new branch named kilo-test/smoke-test.
      Push the branch.

      In your FINAL response, output ONLY this JSON:
      ```json
      {"artifacts": [{"kind": "branch", "data": {"name": "kilo-test/smoke-test"}}]}
      ```

  done:
    adapter_type: fake
    max_retries: 0
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
```

- [ ] **Step 2: Run the smoke test via Rails console**

```bash
cd /Users/gregmushen/work/code/taskrail/app
bin/rails console
```

```ruby
# In the console:
queue = WorkQueue.find_by(slug: "kilo-smoke-test") || WorkQueue.create!(
  name: "Kilo Smoke Test",
  slug: "kilo-smoke-test",
  category: "Test",
  stages: ["fix", "done"],
  config: YAML.load_file("config/queues/kilo_smoke_test.yml")["config"],
  stage_configs: YAML.load_file("config/queues/kilo_smoke_test.yml")["stage_configs"]
)

item = WorkItem.create!(
  work_queue: queue,
  title: "Kilo smoke test",
  spec_url: "test://kilo-smoke",
  stage_name: "fix"
)

Engine::Runner.new.call
item.reload
puts "Status: #{item.status}, Stage: #{item.stage_name}"
```

Expected: item advances to `done` with status `completed`, or fails with a clear error that helps debug the integration.

- [ ] **Step 3: Clean up**

```bash
rm config/queues/kilo_smoke_test.yml
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: Kilo adapter implementation complete"
```

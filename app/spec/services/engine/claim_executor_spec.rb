require "rails_helper"

RSpec.describe Engine::ClaimExecutor do
  it "executes a claim and persists normalized outputs" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test])
    stage_config = StageConfig.create!(
      work_queue: queue,
      stage_name: "build",
      adapter_type: "fake",
      completion_criteria: ["branch_created"],
      timeout_seconds: 600
    )
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)

    described_class.new(claim: claim, stage_config: stage_config).call

    expect(claim.reload).to be_completed
    expect(claim.completed_at).to be_present
    expect(claim.assignment).to include("claim_id" => claim.id)
    expect(claim.reports.success).to exist
    expect(claim.artifacts.where(kind: "branch")).to exist
    expect(claim.trace).to be_present
    expect(claim.trace.stage_name).to eq("build")
    expect(claim.trace.trace_events).to exist
  end

  it "executes shell_script stages" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[test done])
    stage_config = StageConfig.create!(
      work_queue: queue,
      stage_name: "test",
      adapter_type: "shell_script",
      completion_criteria: ["tests_passed"],
      adapter_config: {
        "working_directory" => Rails.root.to_s,
        "commands" => [{ "name" => "unit", "command" => "ruby -e 'exit 0'" }]
      }
    )
    work_item = WorkItem.create!(work_queue: queue, title: "Test thing", spec_url: "opaque spec", stage_name: "test")
    claim = Claim.create!(work_item: work_item, agent_type: "shell_script", status: :active)

    described_class.new(claim: claim, stage_config: stage_config).call

    expect(claim.reload).to be_completed
    expect(claim.artifacts.where(kind: "test_results").first.data["passed"]).to eq(true)
  end

  it "executes inline_claude stages" do
    queue = WorkQueue.create!(name: "Claude Queue", slug: "claude-queue-#{SecureRandom.hex(4)}", stages: %w[intake done])
    stage_config = StageConfig.create!(
      work_queue: queue,
      stage_name: "intake",
      adapter_type: "inline_claude",
      adapter_config: {
        "command" => "claude",
        "args" => ["--print"],
        "working_directory" => Rails.root.to_s,
        "output_artifact_kind" => "agent_report"
      },
      completion_criteria: ["report_present"],
      agent_prompt: "Classify this item."
    )
    work_item = WorkItem.create!(work_queue: queue, title: "Claude smoke", spec_url: "opaque", stage_name: "intake")
    claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)

    runner_result = ClaudeCliRunner::Result.new(stdout: "Looks good", stderr: "", exit_status: 0, duration_ms: 10)
    allow(ClaudeCliRunner).to receive(:new).and_return(instance_double(ClaudeCliRunner, call: runner_result))

    result = described_class.new(claim: claim, stage_config: stage_config).call

    expect(result.status).to eq("success")
    expect(work_item.artifacts.find_by!(kind: "agent_report").data["content"]).to include("Looks good")
    expect(claim.trace.trace_events.pluck(:event_type)).to include("claude_cli")
  end

  it "executes codex stages as async submissions" do
    queue = WorkQueue.create!(name: "Codex Queue", slug: "codex-queue-#{SecureRandom.hex(4)}", stages: %w[build test])
    stage_config = StageConfig.create!(
      work_queue: queue,
      stage_name: "build",
      adapter_type: "codex",
      adapter_config: {
        "command" => "codex",
        "args" => ["exec", "--json"],
        "working_directory" => Rails.root.to_s,
        "output_artifact_kind" => "branch"
      },
      completion_criteria: ["branch_created"],
      agent_prompt: "Build this item."
    )
    work_item = WorkItem.create!(work_queue: queue, title: "Codex build", spec_url: "opaque", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "codex", status: :active)

    submitter_result = CodexCliSubmitter::Result.new(
      stdout: '{"id":"codex-run-1","branch":"taskrail/build-1"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 10,
      external_id: "codex-run-1",
      metadata: { "id" => "codex-run-1", "branch" => "taskrail/build-1" }
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submitter_result))

    result = described_class.new(claim: claim, stage_config: stage_config).call

    expect(result).to be_a(Engine::AsyncAdapterResult)
    expect(claim.reload).to be_active
    expect(claim.async_execution).to eq(true)
    expect(claim.completed_at).to be_nil
    expect(claim.assignment.dig("async", "provider")).to eq("codex")
    expect(claim.assignment.dig("async", "external_id")).to eq("codex-run-1")
  end

  it "leaves claims active when an adapter starts async execution" do
    queue = WorkQueue.create!(name: "Async", slug: "async-#{SecureRandom.hex(4)}", stages: %w[build test])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "async_fake")
    work_item = WorkItem.create!(work_queue: queue, title: "Async build", spec_url: "opaque", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "async_fake", status: :active)

    adapter_class = Class.new do
      def execute(_assignment)
        Engine::AsyncAdapterResult.new(
          provider: "codex",
          external_id: "run-123",
          status: "submitted",
          metadata: { "branch" => "sc-async" },
          trace_events: []
        )
      end
    end

    stub_const("Engine::ClaimExecutor::ADAPTERS", Engine::ClaimExecutor::ADAPTERS.merge("async_fake" => adapter_class))

    result = described_class.new(claim: claim, stage_config: stage_config).call

    expect(result).to be_a(Engine::AsyncAdapterResult)
    expect(claim.reload).to be_active
    expect(claim.async_execution).to eq(true)
    expect(claim.completed_at).to be_nil
    expect(claim.assignment.dig("async", "provider")).to eq("codex")
    expect(claim.assignment.dig("async", "external_id")).to eq("run-123")
  end

  it "marks a claim failed when the adapter raises" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "missing")
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "missing", status: :active)

    expect { described_class.new(claim: claim, stage_config: stage_config).call }.to raise_error(Engine::ClaimExecutor::UnknownAdapter)
    expect(claim.reload).to be_failed
  end
end

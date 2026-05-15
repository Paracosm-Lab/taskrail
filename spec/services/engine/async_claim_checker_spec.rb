require "rails_helper"

RSpec.describe Engine::AsyncClaimChecker do
  it "leaves running codex claims active without transitioning" do
    claim = build_async_claim
    poll_result = CodexCliPoller::Result.new(status: "running", stdout: "", stderr: "", exit_status: 0, duration_ms: 10, metadata: { "status" => "running" })
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: poll_result))

    described_class.new.call

    expect(claim.reload).to be_active
    expect(claim.async_execution).to eq(true)
    expect(claim.completed_at).to be_nil
    expect(claim.work_item.reload.stage_name).to eq("build")
    expect(claim.work_item.transition_logs).to be_empty
  end

  it "persists succeeded codex results and advances after completion" do
    claim = build_async_claim
    poll_result = CodexCliPoller::Result.new(
      status: "succeeded",
      stdout: "done",
      stderr: "",
      exit_status: 0,
      duration_ms: 10,
      metadata: {
        "report" => { "summary" => "Build complete" },
        "artifacts" => [{ "kind" => "branch", "data" => { "name" => "taskrail/build-1" } }]
      }
    )
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: poll_result))

    described_class.new.call

    expect(claim.reload).to be_completed
    expect(claim.async_execution).to eq(false)
    expect(claim.completed_at).to be_present
    expect(claim.reports.last.body["summary"]).to eq("Build complete")
    expect(claim.artifacts.find_by!(kind: "branch").data["name"]).to eq("taskrail/build-1")
    expect(claim.trace.trace_events.pluck(:event_type)).to include("codex_complete")
    expect(claim.work_item.reload.stage_name).to eq("test")
    expect(claim.work_item.transition_logs.last.trigger).to eq("rule_satisfied")
  end

  it "persists failed codex results and lets transition rules retry" do
    claim = build_async_claim
    poll_result = CodexCliPoller::Result.new(status: "failed", stdout: "", stderr: "boom", exit_status: 9, duration_ms: 10, metadata: {})
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: poll_result))

    described_class.new.call

    expect(claim.reload).to be_completed
    expect(claim.async_execution).to eq(false)
    expect(claim.reports.last).to be_failure
    expect(claim.work_item.reload.stage_name).to eq("build")
    expect(claim.work_item.retry_count).to eq(1)
    expect(claim.work_item.transition_logs.last.trigger).to eq("retry")
  end

  def build_async_claim
    queue = WorkQueue.create!(name: "Codex", slug: "codex-#{SecureRandom.hex(4)}", stages: %w[build test])
    StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "codex", completion_criteria: ["branch_created"], adapter_config: { "poll_command" => "codex", "poll_args" => ["status", "--json"] })
    work_item = WorkItem.create!(work_queue: queue, title: "Build feature", spec_url: "opaque", stage_name: "build")
    Claim.create!(
      work_item: work_item,
      agent_type: "codex",
      status: :active,
      async_execution: true,
      started_at: 1.minute.ago,
      assignment: {
        "stage" => { "name" => "build" },
        "model" => "codex-test",
        "async" => { "provider" => "codex", "external_id" => "codex-run-1" }
      }
    )
  end
end

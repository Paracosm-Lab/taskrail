require "rails_helper"

RSpec.describe CheckAsyncClaimsJob, type: :job do
  it "runs the async claim checker" do
    checker = instance_double(Engine::AsyncClaimChecker, call: nil)
    allow(Engine::AsyncClaimChecker).to receive(:new).and_return(checker)

    described_class.perform_now

    expect(checker).to have_received(:call)
  end

  it "leaves a running claim with a fresh heartbeat active" do
    claim = build_async_claim(last_heartbeat_at: 30.seconds.ago)
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: running_poll_result))

    described_class.perform_now

    expect(claim.reload).to be_active
  end

  it "marks a stale async claim failed" do
    claim = build_async_claim(last_heartbeat_at: 5.minutes.ago)

    described_class.perform_now

    expect(claim.reload).to be_failed
    expect(claim.async_execution).to eq(false)
    expect(claim.metadata["error"]).to include("heartbeat stale")
  end

  it "treats nil heartbeat as not stale" do
    claim = build_async_claim(last_heartbeat_at: nil)
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: running_poll_result))

    expect { described_class.perform_now }.not_to raise_error
    expect(claim.reload).to be_active
  end

  it "completes finished async claims and advances the work item" do
    claim = build_async_claim(last_heartbeat_at: 30.seconds.ago)
    poll_result = CodexCliPoller::Result.new(
      status: "succeeded",
      stdout: "done",
      stderr: "",
      exit_status: 0,
      duration_ms: 10,
      metadata: { "artifacts" => [{ "kind" => "branch", "data" => { "name" => "taskrail/build-1" } }] }
    )
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: poll_result))

    described_class.perform_now

    expect(claim.reload).to be_completed
    expect(claim.work_item.reload.stage_name).to eq("test")
  end

  it "does nothing when no async claims exist" do
    expect { described_class.perform_now }.not_to change(Claim, :count)
  end

  def running_poll_result
    CodexCliPoller::Result.new(status: "running", stdout: "", stderr: "", exit_status: 0, duration_ms: 10, metadata: {})
  end

  def build_async_claim(last_heartbeat_at:)
    queue = WorkQueue.create!(name: "Codex", slug: "codex-job-#{SecureRandom.hex(4)}", stages: %w[build test])
    StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "codex", completion_criteria: ["branch_created"], adapter_config: { "poll_command" => "codex" })
    work_item = WorkItem.create!(work_queue: queue, title: "Build", spec_url: "opaque", stage_name: "build")
    Claim.create!(
      work_item: work_item,
      agent_type: "codex",
      status: :active,
      async_execution: true,
      last_heartbeat_at: last_heartbeat_at,
      assignment: { "stage" => { "name" => "build" }, "async" => { "provider" => "codex", "external_id" => "run-1" } }
    )
  end
end

require "rails_helper"

RSpec.describe "codex async workflow", type: :model do
  it "starts async build work and advances only after Codex polling completes" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-codex")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Codex build smoke",
      spec_url: "opaque spec",
      stage_name: "build",
      status: :pending
    )

    submit_result = CodexCliSubmitter::Result.new(
      stdout: '{"id":"codex-run-1"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 13,
      external_id: "codex-run-1",
      metadata: { "id" => "codex-run-1" }
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submit_result))

    processed = Engine::Runner.new.call

    expect(processed).to eq(work_item)
    expect(work_item.reload).to be_pending
    expect(work_item.stage_name).to eq("build")
    expect(work_item.transition_logs).to be_empty

    claim = work_item.claims.order(:created_at).last
    expect(claim.agent_type).to eq("codex")
    expect(claim).to be_active
    expect(claim.async_execution).to eq(true)
    expect(claim.assignment.dig("async", "external_id")).to eq("codex-run-1")
    expect(claim.assignment.dig("stage_config", "agent_prompt")).to eq("[REDACTED]") # redacted by TraceRedactor; "prompt" matches SENSITIVE_KEY_PATTERN
    expect(claim.assignment.dig("stage_config", "completion_criteria")).to include("branch_created", "report_present")
    expect(claim.assignment.dig("stage_config", "adapter_config", "command")).to eq("codex")
    expect(claim.assignment.dig("stage_config", "adapter_config")).not_to have_key("working_directory")

    poll_result = CodexCliPoller::Result.new(
      status: "succeeded",
      stdout: "build complete",
      stderr: "",
      exit_status: 0,
      duration_ms: 17,
      metadata: {
        "report" => { "summary" => "Build complete" },
        "artifacts" => [{ "kind" => "branch", "data" => { "name" => "taskrail/build-smoke" } }]
      }
    )
    allow(CodexCliPoller).to receive(:new).and_return(instance_double(CodexCliPoller, call: poll_result))

    CheckAsyncClaimsJob.perform_now

    expect(claim.reload).to be_completed
    expect(claim.async_execution).to eq(false)
    expect(claim.completed_at).to be_present
    expect(work_item.reload.stage_name).to eq("test")
    expect(work_item).to be_pending
    expect(work_item.artifacts.find_by!(kind: "branch").data["name"]).to eq("taskrail/build-smoke")
    expect(claim.trace.trace_events.pluck(:event_type)).to include("codex_complete")

    transition = work_item.transition_logs.order(:created_at).last
    expect(transition).to have_attributes(
      from_stage: "build",
      to_stage: "test",
      trigger: "rule_satisfied"
    )
  end
end

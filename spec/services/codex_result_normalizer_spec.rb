require "rails_helper"

RSpec.describe CodexResultNormalizer do
  it "turns succeeded poll results into success agent results with branch artifact" do
    claim = build_claim
    poll_result = CodexCliPoller::Result.new(
      status: "succeeded",
      stdout: "implemented feature",
      stderr: "",
      exit_status: 0,
      duration_ms: 25,
      metadata: {
        "report" => { "summary" => "Build complete" },
        "artifacts" => [{ "kind" => "branch", "data" => { "name" => "taskrail/build-1" } }]
      }
    )

    result = described_class.new(claim: claim, poll_result: poll_result).call

    expect(result.status).to eq("success")
    expect(result.report["summary"]).to eq("Build complete")
    expect(result.report["stdout"]).to eq("implemented feature")
    expect(result.report["stage"]).to eq("build")
    expect(result.artifacts.first).to eq("kind" => "branch", "data" => { "name" => "taskrail/build-1" })
    expect(result.trace_events.first["event_type"]).to eq("codex_complete")
    expect(result.trace_events.first["duration_ms"]).to eq(25)
    expect(result.trace_events.first["metadata"]["status"]).to eq("succeeded")
    expect(result.trace_events.first["metadata"]["exit_status"]).to eq(0)
    expect(result.trace_events.first["metadata"]["external_id"]).to eq("codex-run-1")
    expect(result.trace_events.first["metadata"]["model"]).to eq("codex-test")
  end

  it "turns failed poll results into failure agent results" do
    claim = build_claim
    poll_result = CodexCliPoller::Result.new(
      status: "failed",
      stdout: "",
      stderr: "boom",
      exit_status: 9,
      duration_ms: 25,
      metadata: {}
    )

    result = described_class.new(claim: claim, poll_result: poll_result).call

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("failed")
    expect(result.report["stderr"]).to eq("boom")
    expect(result.trace_events.first["event_type"]).to eq("codex_complete")
    expect(result.trace_events.first["metadata"]["status"]).to eq("failed")
  end

  def build_claim
    queue = WorkQueue.create!(name: "Codex", slug: "codex-#{SecureRandom.hex(4)}", stages: %w[build test])
    work_item = WorkItem.create!(work_queue: queue, title: "Build feature", spec_url: "opaque", stage_name: "build")
    Claim.create!(
      work_item: work_item,
      agent_type: "codex",
      status: :active,
      async_execution: true,
      assignment: {
        "stage" => { "name" => "build" },
        "model" => "codex-test",
        "async" => { "provider" => "codex", "external_id" => "codex-run-1" }
      }
    )
  end
end

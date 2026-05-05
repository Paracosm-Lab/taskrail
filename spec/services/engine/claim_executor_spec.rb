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

  it "marks a claim failed when the adapter raises" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "missing")
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "missing", status: :active)

    expect { described_class.new(claim: claim, stage_config: stage_config).call }.to raise_error(Engine::ClaimExecutor::UnknownAdapter)
    expect(claim.reload).to be_failed
  end
end

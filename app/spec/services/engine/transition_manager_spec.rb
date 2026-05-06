require "rails_helper"

RSpec.describe Engine::TransitionManager do
  it "advances to the next stage when criteria pass" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["branch_created"])
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build", retry_count: 2, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "build", status: :success)
    Artifact.create!(claim: claim, work_item: work_item, kind: "branch", data: { "name" => "sc/test" })

    described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("test")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.transition_logs.last.trigger).to eq("rule_satisfied")
    expect(work_item.transition_logs.last.from_stage).to eq("build")
    expect(work_item.transition_logs.last.to_stage).to eq("test")
  end

  it "marks the work item completed when advancing into done" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[review done])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "review", completion_criteria: ["review_verdict"])
    work_item = WorkItem.create!(work_queue: queue, title: "Review thing", spec_url: "opaque spec", stage_name: "review", status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "review", status: :success, body: { "verdict" => "approved" })

    described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("done")
    expect(work_item).to be_completed
  end
end

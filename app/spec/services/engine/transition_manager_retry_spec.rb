require "rails_helper"

RSpec.describe "transition retry and escalation" do
  it "retries failed criteria with feedback when retry budget remains" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test], config: { "default_max_retries" => 3 })
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["branch_created"], max_retries: 3)
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build", retry_count: 0, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "build", status: :success)

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("build")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(1)
    expect(work_item.metadata["feedback"]).to include("missing branch artifact with name")
    expect(work_item.transition_logs.last.trigger).to eq("retry")
  end

  it "blocks failed criteria when retry budget is exhausted" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test], config: { "default_max_retries" => 1 })
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["branch_created"], max_retries: 1)
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build", retry_count: 1, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "build", status: :success)

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_blocked
    expect(work_item.metadata["blocked_reason"]).to include("missing branch artifact with name")
    expect(work_item.metadata.fetch("escalation")).to include(
      "target" => "human",
      "stage_name" => "build",
      "retry_count" => 1,
      "human_action_required" => true
    )
    expect(work_item.metadata.dig("escalation", "reason")).to include("missing branch artifact with name")
    expect(work_item.metadata.dig("escalation", "question")).to include("Work item blocked in build")
    expect(work_item.transition_logs.last.trigger).to eq("blocked")
    expect(work_item.transition_logs.last.details).to include(
      "human_action_required" => true,
      "escalation_target" => "human"
    )
  end
end

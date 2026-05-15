require "rails_helper"

RSpec.describe "decomposition transition" do
  it "creates child items and parks parent as waiting" do
    queue = WorkQueue.create!(
      name: "Development",
      slug: "development-#{SecureRandom.hex(4)}",
      stages: %w[intake decompose build done]
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "decompose", completion_criteria: ["report_present"])
    parent = WorkItem.create!(work_queue: queue, title: "Parent", spec_url: "opaque spec", stage_name: "decompose", status: :claimed)
    claim = Claim.create!(work_item: parent, agent_type: "fake", status: :completed)
    Report.create!(
      claim: claim,
      work_item: parent,
      stage_name: "decompose",
      status: :success,
      body: {
        "children" => [
          { "title" => "Build service", "spec_url" => parent.spec_url, "tags" => { "complexity" => "small" } },
          { "title" => "Add tests", "spec_url" => parent.spec_url, "tags" => { "complexity" => "small" } }
        ]
      }
    )

    Engine::TransitionManager.new(work_item: parent, claim: claim, stage_config: stage_config).call

    expect(parent.reload).to be_waiting
    expect(parent.children.count).to eq(2)
    expect(parent.children.order(:position).pluck(:title)).to eq(["Build service", "Add tests"])
    expect(parent.children.order(:position).pluck(:stage_name)).to eq(%w[build build])
    expect(parent.children.order(:position).pluck(:status)).to eq(%w[pending pending])
    expect(parent.children.order(:position).map(&:tags)).to all(include("complexity" => "small"))
    expect(parent.transition_logs.last.trigger).to eq("decompose")
    expect(parent.transition_logs.last.from_stage).to eq("decompose")
    expect(parent.transition_logs.last.to_stage).to eq("build")
  end

  it "advances a waiting parent when all children are completed" do
    queue = WorkQueue.create!(
      name: "Development",
      slug: "development-#{SecureRandom.hex(4)}",
      stages: %w[intake decompose build done]
    )
    parent = WorkItem.create!(work_queue: queue, title: "Parent", spec_url: "opaque spec", stage_name: "decompose", status: :waiting)
    WorkItem.create!(work_queue: queue, parent: parent, title: "Build service", spec_url: parent.spec_url, stage_name: "build", status: :completed, position: 0)
    WorkItem.create!(work_queue: queue, parent: parent, title: "Add tests", spec_url: parent.spec_url, stage_name: "build", status: :completed, position: 1)

    Engine::TransitionManager.advance_waiting_parent(parent)

    expect(parent.reload.stage_name).to eq("build")
    expect(parent).to be_pending
    expect(parent.transition_logs.last.trigger).to eq("children_completed")
    expect(parent.transition_logs.last.from_stage).to eq("decompose")
    expect(parent.transition_logs.last.to_stage).to eq("build")
  end
end

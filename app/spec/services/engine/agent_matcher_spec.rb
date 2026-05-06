require "rails_helper"

RSpec.describe Engine::AgentMatcher do
  it "returns the current stage config adapter type for MVP" do
    queue = WorkQueue.create!(
      name: "Development",
      slug: "development-#{SecureRandom.hex(4)}",
      stages: %w[intake build done]
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "fake")
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build", tags: { "complexity" => "small" })

    match = described_class.new(work_item: work_item).call

    expect(match.stage_config).to eq(stage_config)
    expect(match.agent_type).to eq("fake")
  end
end

require "rails_helper"

def build_claim(stage_name: "test")
  queue = WorkQueue.create!(name: "Development #{SecureRandom.hex(4)}", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done])
  work_item = WorkItem.create!(title: "Test item", spec_url: "opaque spec", work_queue: queue, stage_name: stage_name)
  Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
end

RSpec.describe Engine::Predicates::TestsPassed do
  it "passes when a test_results artifact has passed true" do
    claim = build_claim
    artifact = Artifact.create!(claim: claim, work_item: claim.work_item, kind: "test_results", data: { "passed" => true })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence[:artifact_id]).to eq(artifact.id)
  end

  it "fails when no passing test_results artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing passing test_results artifact")
  end
end

require "rails_helper"

def build_claim(stage_name: "test")
  queue = WorkQueue.create!(name: "Development #{SecureRandom.hex(4)}", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done])
  work_item = WorkItem.create!(title: "Test item", spec_url: "opaque spec", work_queue: queue, stage_name: stage_name)
  Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
end

RSpec.describe Engine::Predicates::LintClean do
  it "passes when a lint artifact is clean" do
    claim = build_claim
    artifact = Artifact.create!(claim: claim, work_item: claim.work_item, kind: "lint", data: { "clean" => true })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence[:artifact_id]).to eq(artifact.id)
  end

  it "fails when no clean lint artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing clean lint artifact")
  end
end

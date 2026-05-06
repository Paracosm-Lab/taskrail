require "rails_helper"

RSpec.describe Engine::Predicates::CandidatesIdentified do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[scan_references verify_unused]
    )
    work_item = WorkItem.create!(title: "Remove dead code", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_references")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when a removal_candidates artifact exists for the claim" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "removal_candidates",
      data: {
        "dependencies" => ["unused_gem"],
        "files" => [],
        "methods" => [],
        "routes" => [],
        "other" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when no removal_candidates artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_candidates artifact")
  end
end

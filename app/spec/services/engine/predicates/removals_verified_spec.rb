require "rails_helper"

RSpec.describe Engine::Predicates::RemovalsVerified do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[verify_unused draft_removals]
    )
    work_item = WorkItem.create!(title: "Verify removals", spec_url: "opaque spec", work_queue: queue, stage_name: "verify_unused")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when verified_removals contains a safe_to_remove item" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          {
            "type" => "method",
            "name" => "LegacyHelper#unused_method",
            "path" => "app/helpers/legacy_helper.rb",
            "classification" => "safe_to_remove",
            "reasoning" => "No inbound references after dynamic checks."
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, safe_to_remove_count: 1)
  end

  it "fails when verified_removals is absent" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing verified_removals artifact with safe_to_remove removals")
  end

  it "fails when all verified removals need investigation" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          { "type" => "method", "name" => "dynamic_method", "classification" => "needs_investigation" }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing verified_removals artifact with safe_to_remove removals")
  end
end

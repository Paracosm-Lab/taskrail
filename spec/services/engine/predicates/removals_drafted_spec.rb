require "rails_helper"

RSpec.describe Engine::Predicates::RemovalsDrafted do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[draft_removals run_tests]
    )
    work_item = WorkItem.create!(title: "Draft removals", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_removals")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when removal_patches contains at least one patch" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "removal_patches",
      data: {
        "patches" => [
          { "action" => "delete", "path" => "app/helpers/unused_helper.rb", "description" => "Remove unused helper" }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, patch_count: 1)
  end

  it "fails when no removal_patches artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_patches artifact with patches")
  end

  it "fails when removal_patches has an empty patch list" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "removal_patches", data: { "patches" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_patches artifact with patches")
  end
end

require "rails_helper"

RSpec.describe Engine::Predicates::FixesDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Fixes Drafted",
      slug: "fixes-drafted-#{SecureRandom.hex(4)}",
      stages: ["draft", "done"]
    )
    queue.stage_configs.create!(stage_name: "draft", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "draft")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when fix_patches has at least one patch" do
    claim = build_claim(artifacts: [
      { kind: "fix_patches", data: { "patches" => [{ "file" => "app/controllers/payments_controller.rb" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "fix_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, patch_count: 1 })
  end

  it "fails when fix_patches has no patches" do
    claim = build_claim(artifacts: [
      { kind: "fix_patches", data: { "patches" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("fix_patches artifact has no patches")
  end

  it "fails when no fix_patches artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no fix_patches artifact found")
  end
end

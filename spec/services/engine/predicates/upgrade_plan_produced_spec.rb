require "rails_helper"

RSpec.describe Engine::Predicates::UpgradePlanProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-plan-#{SecureRandom.hex(4)}",
      stages: ["prioritize_upgrades", "done"]
    )
    queue.stage_configs.create!(stage_name: "prioritize_upgrades", adapter_type: "fake")
    item = WorkItem.create!(title: "Prioritize upgrades", spec_url: "local", work_queue: queue, stage_name: "prioritize_upgrades")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when upgrade_plan has prioritized upgrades" do
    claim = build_claim(artifacts: [{
      kind: "upgrade_plan",
      data: {
        "upgrades" => [
          { "deps" => ["rack"], "priority" => 1, "risk" => "medium", "notes" => "CVE fix" },
          { "deps" => ["puma"], "priority" => 2, "risk" => "low", "notes" => "patch" }
        ]
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "upgrade_plan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, upgrade_count: 2, highest_priority: 1 })
  end

  it "fails when the upgrade_plan artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no upgrade_plan artifact found")
  end

  it "fails when upgrade_plan has no upgrades" do
    claim = build_claim(artifacts: [{ kind: "upgrade_plan", data: { "upgrades" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_plan artifact has no upgrades")
  end

  it "fails when an upgrade has no dependency names" do
    claim = build_claim(artifacts: [{ kind: "upgrade_plan", data: { "upgrades" => [{ "deps" => [], "priority" => 1, "risk" => "low" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_plan upgrade is missing deps")
  end
end

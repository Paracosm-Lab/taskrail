require "rails_helper"

RSpec.describe Engine::Predicates::UpgradeDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-draft-#{SecureRandom.hex(4)}",
      stages: ["upgrade_one", "done"]
    )
    queue.stage_configs.create!(stage_name: "upgrade_one", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft upgrade", spec_url: "local", work_queue: queue, stage_name: "upgrade_one")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when upgrade_patches has a version change and patches" do
    claim = build_claim(artifacts: [{
      kind: "upgrade_patches",
      data: {
        "dep_name" => "rack",
        "from_version" => "2.2.8",
        "to_version" => "3.0.9",
        "branch_name" => "dependency-upgrade/rack-3-0-9",
        "patches" => [
          { "file" => "Gemfile", "original" => "gem \"rack\", \"~> 2.2.8\"", "replacement" => "gem \"rack\", \"~> 3.0.9\"" }
        ]
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "upgrade_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, dep_name: "rack", patch_count: 1 })
  end

  it "fails when the upgrade_patches artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no upgrade_patches artifact found")
  end

  it "fails when the dependency name is missing" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "from_version" => "2.2.8", "to_version" => "3.0.9", "branch_name" => "dependency-upgrade/rack", "patches" => [{ "file" => "Gemfile" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact is missing dep_name")
  end

  it "fails when the version did not change" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "2.2.8", "branch_name" => "dependency-upgrade/rack", "patches" => [{ "file" => "Gemfile" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact has no version change")
  end

  it "fails when no patches are included" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "3.0.9", "branch_name" => "dependency-upgrade/rack", "patches" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact has no patches")
  end
end

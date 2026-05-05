require "rails_helper"

RSpec.describe Engine::Predicates::ClustersCreated do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Ops ClustersCreated", slug: "ops-clusters-#{SecureRandom.hex(4)}", stages: ["cluster", "done"])
    queue.stage_configs.create!(stage_name: "cluster", adapter_type: "fake")
    item = WorkItem.create!(title: "Test", spec_url: "opaque spec", work_queue: queue, stage_name: "cluster")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when clusters artifact exists" do
    claim = build_claim(artifacts: [{ kind: "clusters", data: { "clusters" => [{ "name" => "db-pool" }] } }])
    artifact = claim.artifacts.find_by!(kind: "clusters")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no clusters artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no clusters artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "other_kind", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no clusters artifact found")
  end
end

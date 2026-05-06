require "rails_helper"

RSpec.describe Engine::Predicates::RunbookMapped do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Ops RunbookMapped", slug: "ops-runbook-mapping-#{SecureRandom.hex(4)}", stages: ["map", "done"])
    queue.stage_configs.create!(stage_name: "map", adapter_type: "fake")
    item = WorkItem.create!(title: "Test", spec_url: "opaque spec", work_queue: queue, stage_name: "map")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when runbook mapping artifact exists" do
    claim = build_claim(artifacts: [{ kind: "runbook_mapping", data: { "mappings" => [{ "cluster" => "db-pool" }] } }])
    artifact = claim.artifacts.find_by!(kind: "runbook_mapping")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no runbook mapping artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no runbook mapping artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "clusters", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no runbook mapping artifact found")
  end
end

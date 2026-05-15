require "rails_helper"

RSpec.describe Engine::Predicates::DependenciesMapped do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Credential Rotation #{SecureRandom.hex(4)}", slug: "credential-rotation-deps-#{SecureRandom.hex(4)}", stages: ["map_dependencies", "done"])
    queue.stage_configs.create!(stage_name: "map_dependencies", adapter_type: "fake")
    item = WorkItem.create!(title: "Map credential dependencies", spec_url: "opaque spec", work_queue: queue, stage_name: "map_dependencies")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with a credential count when a dependency_map artifact has a credentials array" do
    claim = build_claim(artifacts: [{ kind: "dependency_map", data: { "credentials" => [{ "name" => "STRIPE_SECRET_KEY", "type" => "payment_api_key" }] } }])
    artifact = claim.artifacts.find_by!(kind: "dependency_map")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, credential_count: 1 })
  end

  it "fails when no dependency_map artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing dependency_map artifact")
  end

  it "fails when the dependency_map artifact does not contain a credentials array" do
    claim = build_claim(artifacts: [{ kind: "dependency_map", data: { "summary" => "not structured" } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("dependency_map artifact has no credentials array")
  end
end

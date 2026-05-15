require "rails_helper"

RSpec.describe Engine::Predicates::BoundariesIdentified do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Integration Boundaries #{SecureRandom.hex(4)}",
      slug: "integration-boundaries-#{SecureRandom.hex(4)}",
      stages: %w[identify_boundaries done]
    )
    queue.stage_configs.create!(stage_name: "identify_boundaries", adapter_type: "fake")
    item = WorkItem.create!(title: "Identify boundaries", spec_url: "opaque spec", work_queue: queue, stage_name: "identify_boundaries")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed, started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when a boundary_map artifact has boundaries for each flow" do
    claim = build_claim(
      artifacts: [
        {
          kind: "boundary_map",
          data: {
            "flows" => [
              {
                "name" => "Create work item and advance",
                "boundaries" => [
                  { "from" => "API", "to" => "WorkItem", "contract" => "persist item", "stub_strategy" => "real database" },
                  { "from" => "Engine::Runner", "to" => "Adapters::FakeAdapter", "contract" => "claim assignment", "stub_strategy" => "fake adapter" }
                ],
                "setup_data" => ["integration_tests queue"],
                "teardown" => "database cleanup"
              }
            ]
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "boundary_map")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, flows_count: 1, boundaries_count: 2 })
  end

  it "fails when the boundary_map artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no boundary_map artifact found")
  end

  it "fails when the boundary_map has no flows" do
    claim = build_claim(artifacts: [{ kind: "boundary_map", data: { "flows" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("boundary_map artifact has no flows")
  end

  it "fails when any flow has no boundaries" do
    claim = build_claim(
      artifacts: [
        { kind: "boundary_map", data: { "flows" => [{ "name" => "Incomplete", "boundaries" => [] }] } }
      ]
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("boundary_map artifact has flows without boundaries: Incomplete")
  end
end

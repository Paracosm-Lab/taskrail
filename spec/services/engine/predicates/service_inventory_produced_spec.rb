require "rails_helper"

RSpec.describe Engine::Predicates::ServiceInventoryProduced do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[inventory]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", spec_url: "local", stage_name: "inventory") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: :active) }

  it "passes with evidence when a service inventory artifact has at least one service" do
    artifact = claim.artifacts.create!(work_item: work_item,
      kind: "service_inventory",
      data: { "services" => [{ "name" => "taskrail-api", "type" => "web" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when the inventory artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing service_inventory artifact with services")
  end

  it "fails when the inventory has no services" do
    claim.artifacts.create!(work_item: work_item, kind: "service_inventory", data: { "services" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing service_inventory artifact with services")
  end
end

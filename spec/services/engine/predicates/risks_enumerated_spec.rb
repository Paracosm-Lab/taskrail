require "rails_helper"

RSpec.describe Engine::Predicates::RisksEnumerated do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[enumerate_risks done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "enumerate_risks") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", assignment: { "stage_name" => "enumerate_risks" }, status: :active) }

  it "passes with evidence when risks include allowed severities" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "risks" => [
          { "category" => "downtime", "description" => "table rewrite lock", "severity" => "blocking", "affected_paths" => ["db/migrate/unsafe.rb"], "mitigation" => "split migration" },
          { "category" => "backwards_compatibility", "description" => "old code misses default", "severity" => "medium", "affected_paths" => ["app/models/order.rb"], "mitigation" => "dual read" }
        ],
        "blocking_risks" => ["table rewrite lock"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, risks_count: 2, blocking_risks_count: 1)
  end

  it "fails when the risk_assessment artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no risk_assessment artifact found")
  end

  it "fails when risks are empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "risk_assessment", data: { "risks" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment artifact has no risks")
  end

  it "fails when a risk has an unknown severity" do
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: { "risks" => [{ "severity" => "catastrophic" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment contains unknown severity")
  end
end

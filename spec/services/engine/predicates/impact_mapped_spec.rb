require "rails_helper"

RSpec.describe Engine::Predicates::ImpactMapped do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[scan_impact done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "scan_impact") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", assignment: { "stage_name" => "scan_impact" }, status: :active) }

  it "passes with evidence when the impact_map has affected files" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "impact_map",
      data: {
        "affected_files" => ["app/models/order.rb", "db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
        "affected_tests" => ["spec/models/order_spec.rb"],
        "affected_configs" => ["config/database.yml"],
        "external_consumers" => ["billing-export"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(
      artifact_id: artifact.id,
      affected_files_count: 2,
      affected_tests_count: 1,
      affected_configs_count: 1,
      external_consumers_count: 1
    )
  end

  it "fails when the artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no impact_map artifact found")
  end

  it "fails when affected_files is empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "impact_map", data: { "affected_files" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("impact_map artifact has no affected files")
  end
end

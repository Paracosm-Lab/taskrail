require "rails_helper"

RSpec.describe Engine::Predicates::RollbackTested do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[test_rollback done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "test_rollback") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", assignment: { "stage_name" => "test_rollback" }, status: :active) }

  it "passes with evidence when rollback test results are fully green" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => true,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when rollback_test_results is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no rollback_test_results artifact found")
  end

  it "fails when any required check is false" do
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => false,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => ["rollback command failed"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_test_results has failed checks: rollback_succeeded")
  end
end

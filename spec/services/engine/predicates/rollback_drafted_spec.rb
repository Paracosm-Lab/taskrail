require "rails_helper"

RSpec.describe Engine::Predicates::RollbackDrafted do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[draft_rollback done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "draft_rollback") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", assignment: { "stage_name" => "draft_rollback" }, status: :active) }

  it "passes with evidence when rollback_plan has procedures and steps" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_plan",
      data: {
        "procedures" => [
          {
            "risk_ref" => "table rewrite lock",
            "steps" => [
              { "action" => "restore previous schema", "command" => "bin/rails db:rollback STEP=1", "verification" => "orders.region absent" }
            ],
            "estimated_time" => "5 minutes",
            "data_loss_potential" => "none"
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, procedures_count: 1, steps_count: 1)
  end

  it "fails when the rollback_plan artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no rollback_plan artifact found")
  end

  it "fails when procedures are empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "rollback_plan", data: { "procedures" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_plan artifact has no procedures")
  end

  it "fails when a procedure has no testable steps" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "rollback_plan", data: { "procedures" => [{ "risk_ref" => "lock", "steps" => [] }] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_plan procedures require testable steps")
  end
end

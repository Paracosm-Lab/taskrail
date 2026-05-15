require "rails_helper"

RSpec.describe Engine::Predicates::ReadinessScored do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[score]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", spec_url: "local", stage_name: "score") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: :active) }

  before do
    claim.artifacts.create!(work_item: work_item,
      kind: "service_inventory",
      data: { "services" => [{ "name" => "api" }, { "name" => "worker" }] }
    )
  end

  it "passes when every inventoried service has a readiness score" do
    artifact = claim.artifacts.create!(work_item: work_item,
      kind: "readiness_scores",
      data: {
        "services" => [
          { "name" => "api", "scores" => { "health_checks" => 3 }, "total_score" => 80, "grade" => "B" },
          { "name" => "worker", "scores" => { "health_checks" => 1 }, "total_score" => 40, "grade" => "C" }
        ],
        "summary" => { "avg_score" => 60, "worst_service" => "worker", "best_service" => "api" }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when a service is missing a score" do
    claim.artifacts.create!(work_item: work_item,
      kind: "readiness_scores",
      data: { "services" => [{ "name" => "api", "scores" => {}, "total_score" => 80, "grade" => "B" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("readiness_scores missing scores for inventoried services")
  end
end

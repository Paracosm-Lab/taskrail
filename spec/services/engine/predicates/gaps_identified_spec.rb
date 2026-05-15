require "rails_helper"

RSpec.describe Engine::Predicates::GapsIdentified do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[gaps]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", spec_url: "local", stage_name: "gaps") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: :active) }

  it "passes with evidence when gap analysis contains prioritized gaps" do
    artifact = claim.artifacts.create!(work_item: work_item,
      kind: "gap_analysis",
      data: {
        "platform_gaps" => [{ "gap" => "No dashboards" }],
        "service_gaps" => [],
        "priority_order" => ["platform:no-dashboards"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when gap analysis is absent or empty" do
    claim.artifacts.create!(work_item: work_item, kind: "gap_analysis", data: { "platform_gaps" => [], "service_gaps" => [], "priority_order" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing non-empty gap_analysis artifact")
  end
end

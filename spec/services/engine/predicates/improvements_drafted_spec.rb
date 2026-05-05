require "rails_helper"

RSpec.describe Engine::Predicates::ImprovementsDrafted do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[draft]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", spec_url: "local", stage_name: "draft") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: :active) }

  it "passes with evidence when at least one improvement includes file content" do
    artifact = claim.artifacts.create!(work_item: work_item,
      kind: "improvement_drafts",
      data: {
        "improvements" => [
          {
            "service" => "api",
            "gap_type" => "health_checks",
            "files" => [{ "path" => "config/routes.rb", "content" => "get '/health'" }]
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when drafts are missing file content" do
    claim.artifacts.create!(work_item: work_item, kind: "improvement_drafts", data: { "improvements" => [{ "service" => "api", "files" => [] }] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing improvement_drafts artifact with file content")
  end
end

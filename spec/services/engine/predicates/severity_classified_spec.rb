require "rails_helper"

RSpec.describe Engine::Predicates::SeverityClassified do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Severity Classified",
      slug: "severity-classified-#{SecureRandom.hex(4)}",
      stages: ["classify", "done"]
    )
    queue.stage_configs.create!(stage_name: "classify", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "classify")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when severity_report has findings" do
    claim = build_claim(artifacts: [
      { kind: "severity_report", data: { "findings" => [{ "severity" => "high" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "severity_report")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, finding_count: 1 })
  end

  it "fails when severity_report has no findings" do
    claim = build_claim(artifacts: [
      { kind: "severity_report", data: { "findings" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("severity_report artifact has no findings")
  end

  it "fails when no severity_report artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no severity_report artifact found")
  end
end

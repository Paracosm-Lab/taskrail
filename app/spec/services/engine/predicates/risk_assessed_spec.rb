require "rails_helper"

RSpec.describe Engine::Predicates::RiskAssessed do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Credential Rotation #{SecureRandom.hex(4)}", slug: "credential-rotation-risk-#{SecureRandom.hex(4)}", stages: ["assess_risk", "done"])
    queue.stage_configs.create!(stage_name: "assess_risk", adapter_type: "fake")
    item = WorkItem.create!(title: "Assess credential risk", spec_url: "opaque spec", work_queue: queue, stage_name: "assess_risk")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when a risk_assessment artifact has credentials and summary" do
    claim = build_claim(artifacts: [{ kind: "risk_assessment", data: { "credentials" => [{ "name" => "STRIPE_SECRET_KEY", "overall_risk" => "critical" }], "critical_count" => 1, "summary" => "One critical credential." } }])
    artifact = claim.artifacts.find_by!(kind: "risk_assessment")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, critical_count: 1, credential_count: 1 })
  end

  it "fails when no risk_assessment artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing risk_assessment artifact")
  end

  it "fails when the risk_assessment artifact does not contain a credentials array" do
    claim = build_claim(artifacts: [{ kind: "risk_assessment", data: { "summary" => "not structured" } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment artifact has no credentials array")
  end

  it "fails when the risk_assessment artifact does not contain a summary" do
    claim = build_claim(artifacts: [{ kind: "risk_assessment", data: { "credentials" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment artifact has no summary")
  end
end

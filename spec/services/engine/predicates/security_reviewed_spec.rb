require "rails_helper"

RSpec.describe Engine::Predicates::SecurityReviewed do
  def build_claim
    queue = WorkQueue.create!(name: "PR Review #{SecureRandom.hex(4)}", slug: "pr-review-sec-#{SecureRandom.hex(4)}", stages: %w[security_scan coverage_check])
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/2", work_queue: queue, stage_name: "security_scan")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when a security_findings artifact exists with no blocking findings" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "security_findings",
      data: { "findings" => [{ "severity" => "warning", "category" => "dependency" }], "blocking_count" => 0 }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, findings_count: 1, blocking_count: 0)
  end

  it "passes when zero findings are present" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "security_findings", data: { "findings" => [], "blocking_count" => 0 })

    expect(described_class.new(claim: claim).call).to be_passed
  end

  it "fails when the security_findings artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing security_findings artifact")
  end

  it "fails when blocking security findings exist" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "security_findings",
      data: { "findings" => [{ "severity" => "blocking", "category" => "sql_injection" }], "blocking_count" => 1 }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("blocking security findings: 1")
  end
end

require "rails_helper"

RSpec.describe Engine::Predicates::QueryAnalyzed do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Analyzed #{SecureRandom.hex(4)}", slug: "query-analyzed-#{SecureRandom.hex(4)}", stages: ["analyze_performance", "done"])
    queue.stage_configs.create!(stage_name: "analyze_performance", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "analyze_performance")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_analysis artifact has findings" do
    claim = build_claim(artifacts: [{ kind: "query_analysis", data: { "findings" => [{ "issue_type" => "missing_index" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_analysis")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, finding_count: 1 })
  end

  it "fails when query_analysis artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_analysis artifact found")
  end

  it "fails when query_analysis has no findings" do
    claim = build_claim(artifacts: [{ kind: "query_analysis", data: { "findings" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_analysis artifact has no findings")
  end
end

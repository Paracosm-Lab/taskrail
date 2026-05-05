require "rails_helper"

RSpec.describe Engine::Predicates::QueryInventoryProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Inventory #{SecureRandom.hex(4)}", slug: "query-inventory-#{SecureRandom.hex(4)}", stages: ["collect_queries", "done"])
    queue.stage_configs.create!(stage_name: "collect_queries", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "collect_queries")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_inventory artifact has at least one query" do
    claim = build_claim(artifacts: [{ kind: "query_inventory", data: { "queries" => [{ "sql" => "SELECT * FROM posts" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, query_count: 1 })
  end

  it "fails when query_inventory artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_inventory artifact found")
  end

  it "fails when query_inventory has no queries" do
    claim = build_claim(artifacts: [{ kind: "query_inventory", data: { "queries" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_inventory artifact has no queries")
  end
end

require "rails_helper"

RSpec.describe Engine::Predicates::EndpointInventoryProduced do
  def build_claim(reports: [])
    queue = WorkQueue.create!(name: "API Docs", slug: "api-docs-#{SecureRandom.hex(4)}", stages: ["scan", "done"])
    queue.stage_configs.create!(stage_name: "scan", adapter_type: "fake")
    item = WorkItem.create!(title: "Sync docs", spec_url: "opaque spec", work_queue: queue, stage_name: "scan")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    reports.each_with_index do |report, index|
      created_at = report.delete(:created_at) || index.minutes.ago
      Report.create!(work_item: item, claim: claim, stage_name: "scan", created_at: created_at, updated_at: created_at, **report)
    end
    claim
  end

  it "passes when the latest success report has endpoint_inventory with endpoints" do
    claim = build_claim(reports: [
      { status: :success, body: { "endpoint_inventory" => { "framework" => "rails", "endpoints" => [{ "method" => "GET", "path" => "/api/v1/widgets" }] } } }
    ])
    report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id, endpoint_count: 1 })
  end

  it "passes when the report uses generic artifact wrapper shape" do
    claim = build_claim(reports: [
      { status: :success, body: { "artifact_kind" => "endpoint_inventory", "artifact" => { "endpoints" => [{ "method" => "POST", "path" => "/api/v1/widgets" }] } } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence.fetch(:endpoint_count)).to eq(1)
  end

  it "fails when endpoint inventory is missing" do
    claim = build_claim(reports: [{ status: :success, body: {} }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("endpoint inventory artifact missing")
  end

  it "fails when endpoint list is empty" do
    claim = build_claim(reports: [{ status: :success, body: { "endpoint_inventory" => { "endpoints" => [] } } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("endpoint inventory has no endpoints")
  end

  it "uses the newest success report by creation time" do
    claim = build_claim(reports: [
      { status: :success, body: { "endpoint_inventory" => { "endpoints" => [] } }, created_at: 2.minutes.ago },
      { status: :success, body: { "endpoint_inventory" => { "endpoints" => [{ "method" => "GET", "path" => "/new" }] } }, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
  end

end

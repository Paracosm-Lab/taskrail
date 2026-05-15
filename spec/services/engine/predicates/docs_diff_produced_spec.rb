require "rails_helper"

RSpec.describe Engine::Predicates::DocsDiffProduced do
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

  it "passes when latest success report has docs_diff artifact" do
    claim = build_claim(reports: [
      { status: :success, body: { "docs_diff" => { "missing" => [], "stale" => [], "incorrect" => [], "undocumented_behavior" => [], "coverage_pct" => 100.0 } } }
    ])
    report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id, missing_count: 0, stale_count: 0, incorrect_count: 0 })
  end

  it "passes when latest success report uses generic artifact wrapper" do
    claim = build_claim(reports: [
      { status: :success, body: { "artifact_kind" => "docs_diff", "artifact" => { "missing" => [{ "path" => "/api/v1/widgets" }] } } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence.fetch(:missing_count)).to eq(1)
  end

  it "fails when docs_diff is missing" do
    claim = build_claim(reports: [{ status: :success, body: {} }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("docs diff artifact missing")
  end

  it "uses the newest success report by creation time" do
    claim = build_claim(reports: [
      { status: :success, body: {}, created_at: 2.minutes.ago },
      { status: :success, body: { "docs_diff" => { "missing" => [{ "path" => "/new" }] } }, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence.fetch(:missing_count)).to eq(1)
  end

  it "ignores newer non-success reports" do
    claim = build_claim(reports: [
      { status: :success, body: { "docs_diff" => { "missing" => [] } }, created_at: 2.minutes.ago },
      { status: :failure, body: {}, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
  end

end

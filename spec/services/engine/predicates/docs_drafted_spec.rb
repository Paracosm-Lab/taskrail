require "rails_helper"

RSpec.describe Engine::Predicates::DocsDrafted do
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

  it "passes when draft docs include at least one file" do
    claim = build_claim(reports: [
      { status: :success, body: { "draft_docs" => { "format" => "openapi_yaml", "files" => [{ "path" => "docs/openapi.yml", "content" => "openapi: 3.1.0", "change_type" => "update" }] } } }
    ])
    report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id, file_count: 1, format: "openapi_yaml" })
  end

  it "passes when latest success report uses generic artifact wrapper" do
    claim = build_claim(reports: [
      { status: :success, body: { "artifact_kind" => "draft_docs", "artifact" => { "format" => "markdown", "files" => [{ "path" => "docs/api.md" }] } } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence.fetch(:file_count)).to eq(1)
  end

  it "fails when draft_docs is missing" do
    claim = build_claim(reports: [{ status: :success, body: {} }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("draft docs artifact missing")
  end

  it "fails when files list is empty" do
    claim = build_claim(reports: [{ status: :success, body: { "draft_docs" => { "files" => [] } } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("draft docs has no files")
  end

  it "uses the newest success report by creation time" do
    claim = build_claim(reports: [
      { status: :success, body: { "draft_docs" => { "files" => [] } }, created_at: 2.minutes.ago },
      { status: :success, body: { "draft_docs" => { "files" => [{ "path" => "docs/api.md" }] } }, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
  end

end

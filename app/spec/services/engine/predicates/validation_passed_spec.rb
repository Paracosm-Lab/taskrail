require "rails_helper"

RSpec.describe Engine::Predicates::ValidationPassed do
  def build_claim(reports: [])
    queue = WorkQueue.create!(name: "Ops Validation", slug: "ops-validation-#{SecureRandom.hex(4)}", stages: ["validate", "done"])
    queue.stage_configs.create!(stage_name: "validate", adapter_type: "fake")
    item = WorkItem.create!(title: "Test", spec_url: "opaque spec", work_queue: queue, stage_name: "validate")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    reports.each_with_index do |report, index|
      created_at = report.delete(:created_at) || index.minutes.ago
      Report.create!(work_item: item, claim: claim, stage_name: "validate", created_at: created_at, updated_at: created_at, **report)
    end
    claim
  end

  it "passes when the latest success report has validation_passed true" do
    claim = build_claim(reports: [{ status: :success, body: { "validation_passed" => true } }])
    report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id })
  end

  it "fails when the latest success report has validation_passed false" do
    claim = build_claim(reports: [{ status: :success, body: { "validation_passed" => false } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("staging validation did not pass")
  end

  it "uses the newest success report by creation time" do
    claim = build_claim(reports: [
      { status: :success, body: { "validation_passed" => true }, created_at: 2.minutes.ago },
      { status: :success, body: { "validation_passed" => false }, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
  end

  it "ignores newer non-success reports" do
    claim = build_claim(reports: [
      { status: :success, body: { "validation_passed" => true }, created_at: 2.minutes.ago },
      { status: :failure, body: { "validation_passed" => false }, created_at: 1.minute.ago }
    ])
    success_report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: success_report.id })
  end
end

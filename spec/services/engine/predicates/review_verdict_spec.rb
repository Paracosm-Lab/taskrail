require "rails_helper"

def build_claim(stage_name: "test")
  queue = WorkQueue.create!(name: "Development #{SecureRandom.hex(4)}", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done])
  work_item = WorkItem.create!(title: "Test item", spec_url: "opaque spec", work_queue: queue, stage_name: stage_name)
  Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
end

RSpec.describe Engine::Predicates::ReviewVerdict do
  it "passes when the report verdict is approved" do
    claim = build_claim(stage_name: "review")
    report = Report.create!(claim: claim, work_item: claim.work_item, stage_name: "review", status: :success, body: { "verdict" => "approved" })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence[:report_id]).to eq(report.id)
  end

  it "fails when no approved review verdict exists" do
    claim = build_claim(stage_name: "review")
    Report.create!(claim: claim, work_item: claim.work_item, stage_name: "review", status: :failure, body: { "verdict" => "request_changes" })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing approved review verdict")
  end
end

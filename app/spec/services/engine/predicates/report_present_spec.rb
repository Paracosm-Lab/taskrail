require "rails_helper"

def build_claim(stage_name: "test")
  queue = WorkQueue.create!(name: "Development #{SecureRandom.hex(4)}", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done])
  work_item = WorkItem.create!(title: "Test item", spec_url: "opaque spec", work_queue: queue, stage_name: stage_name)
  Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
end

RSpec.describe Engine::Predicates::ReportPresent do
  it "passes when a success report exists for the claim" do
    claim = build_claim
    report = Report.create!(claim: claim, work_item: claim.work_item, stage_name: claim.work_item.stage_name, status: :success)

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence[:report_id]).to eq(report.id)
  end

  it "fails when no success report exists for the claim" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing success report")
  end
end

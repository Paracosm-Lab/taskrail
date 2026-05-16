require "rails_helper"

RSpec.describe DashboardPayloadBuilder do
  it "returns bounded snapshots with truncation metadata" do
    queue = WorkQueue.create!(name: "Development", slug: "development-dashboard", stages: %w[intake done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake")
    3.times { |index| WorkItem.create!(work_queue: queue, title: "Active #{index}", spec_url: "opaque", stage_name: "intake") }
    12.times { |index| WorkItem.create!(work_queue: queue, title: "Done #{index}", spec_url: "opaque", stage_name: "done", status: :completed) }

    payload = described_class.snapshot(queue_slug: queue.slug, limit: 2)

    expect(payload.fetch(:event_type)).to eq("snapshot")
    expect(payload.fetch(:work_items).size).to eq(12)
    expect(payload.fetch(:meta)).to include(active_truncated: true, completed_truncated: true)
    expect(payload.fetch(:cursor)).to be_present
  end

  it "caches cost totals for a short interval" do
    queue = WorkQueue.create!(name: "Development", slug: "development-cost-cache", stages: %w[intake done])
    work_item = WorkItem.create!(work_queue: queue, title: "Costly", spec_url: "opaque", stage_name: "intake")
    claim = Claim.create!(work_item: work_item, agent_type: "fake")
    Trace.create!(claim: claim, work_item: work_item, stage_name: "intake", agent_type: "fake", total_tokens_in: 10)

    first = described_class.snapshot(queue_slug: queue.slug).fetch(:total_costs)
    second = described_class.snapshot(queue_slug: queue.slug).fetch(:total_costs)

    expect(second).to eq(first)
  end
end

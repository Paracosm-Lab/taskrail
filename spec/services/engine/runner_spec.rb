require "rails_helper"

RSpec.describe Engine::Runner do
  it "claims exactly one pending work item" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake decompose done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake", completion_criteria: ["report_present"])
    first = WorkItem.create!(work_queue: queue, title: "First", spec_url: "opaque spec", stage_name: "intake", status: :pending)
    second = WorkItem.create!(work_queue: queue, title: "Second", spec_url: "opaque spec", stage_name: "intake", status: :pending)

    processed = described_class.new.call

    expect(processed).to eq(first)
    expect(first.reload.claims.count).to eq(1)
    expect(second.reload.claims.count).to eq(0)
  end

  it "skips work items with active claims" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake decompose done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake", completion_criteria: ["report_present"])
    busy = WorkItem.create!(work_queue: queue, title: "Busy", spec_url: "opaque spec", stage_name: "intake", status: :pending)
    Claim.create!(work_item: busy, agent_type: "fake", status: :active)
    ready = WorkItem.create!(work_queue: queue, title: "Ready", spec_url: "opaque spec", stage_name: "intake", status: :pending)

    processed = described_class.new.call

    expect(processed).to eq(ready)
    expect(busy.reload.claims.active.count).to eq(1)
    expect(ready.reload.claims.count).to eq(1)
  end

  it "skips non-pending work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake decompose done])
    %i[blocked waiting completed cancelled].each do |status|
      WorkItem.create!(work_queue: queue, title: status.to_s, spec_url: "opaque spec", stage_name: "intake", status: status)
    end

    expect(described_class.new.call).to be_nil
  end

  it "runs through fake intake and advances to decompose" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake decompose done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake", completion_criteria: ["report_present"])
    work_item = WorkItem.create!(work_queue: queue, title: "Add calendar", spec_url: "opaque spec", stage_name: "intake", status: :pending)

    described_class.new.call

    expect(work_item.reload.stage_name).to eq("decompose")
    expect(work_item).to be_pending
    expect(work_item.claims.completed.count).to eq(1)
    expect(work_item.reports.count).to eq(1)
    expect(work_item.transition_logs.last.trigger).to eq("rule_satisfied")
  end
end

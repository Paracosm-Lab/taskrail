require "rails_helper"

RSpec.describe "fake development workflow" do
  it "processes a work item through the development queue" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development")
    work_item = WorkItem.create!(title: "Add calendar event", spec_url: "opaque spec", work_queue: queue, stage_name: "intake")

    40.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.claims.count).to be >= 1
    expect(work_item.transition_logs.pluck(:trigger)).to include("rule_satisfied")
    expect(Trace.sum(:total_duration_ms)).to be >= 0
  end
end

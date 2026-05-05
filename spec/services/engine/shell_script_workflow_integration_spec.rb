require "rails_helper"

RSpec.describe "shell script workflow", type: :model do
  it "advances from test to review using shell-produced artifacts" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-shell")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Shell validation smoke",
      spec_url: "opaque spec",
      stage_name: "test",
      status: :pending
    )

    processed = Engine::Runner.new.call

    expect(processed).to eq(work_item)
    expect(work_item.reload.stage_name).to eq("review")
    expect(work_item).to be_pending

    claim = work_item.claims.order(:created_at).last
    expect(claim.agent_type).to eq("shell_script")
    expect(claim.trace.trace_events.pluck(:event_type)).to include("shell_command")

    test_results = work_item.artifacts.find_by!(kind: "test_results")
    lint = work_item.artifacts.find_by!(kind: "lint")
    coverage = work_item.artifacts.find_by!(kind: "coverage")

    expect(test_results.data["passed"]).to eq(true)
    expect(lint.data["clean"]).to eq(true)
    expect(coverage.data["current"]).to be >= coverage.data["previous"]

    transition = work_item.transition_logs.order(:created_at).last
    expect(transition).to have_attributes(
      from_stage: "test",
      to_stage: "review",
      trigger: "rule_satisfied"
    )
  end
end

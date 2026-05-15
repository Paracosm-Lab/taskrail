require "rails_helper"

RSpec.describe "inline Claude workflow", type: :model do
  it "advances from intake to decompose using Claude-produced report evidence" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-claude")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Claude intake smoke",
      spec_url: "opaque spec",
      stage_name: "intake",
      status: :pending
    )

    runner_result = ClaudeCliRunner::Result.new(stdout: "Classification complete", stderr: "", exit_status: 0, duration_ms: 11)
    allow(ClaudeCliRunner).to receive(:new).and_return(instance_double(ClaudeCliRunner, call: runner_result))

    processed = Engine::Runner.new.call

    expect(processed).to eq(work_item)
    expect(work_item.reload.stage_name).to eq("decompose")
    claim = work_item.claims.order(:created_at).last
    expect(claim.agent_type).to eq("inline_claude")
    expect(claim.trace.trace_events.pluck(:event_type)).to include("claude_cli")
    expect(work_item.reports.last.body["response"]).to include("Classification complete")
    expect(work_item.transition_logs.last).to have_attributes(
      from_stage: "intake",
      to_stage: "decompose",
      trigger: "rule_satisfied"
    )
  end
end

require "rails_helper"

RSpec.describe "Chaos cross-queue response waiting" do
  it "advances a waiting chaos parent when the response child is completed" do
    chaos_queue = WorkQueue.create!(name: "Chaos Monkey", slug: "chaos-wait-#{SecureRandom.hex(4)}", stages: %w[hold_for_response evaluate_recovery done])
    response_queue = WorkQueue.create!(name: "Chaos Response", slug: "chaos-response-wait-#{SecureRandom.hex(4)}", stages: %w[detect_alerts report_outcome done])

    parent = WorkItem.create!(
      title: "Chaos exercise",
      spec_url: "inline",
      work_queue: chaos_queue,
      stage_name: "hold_for_response",
      status: :waiting
    )
    WorkItem.create!(
      title: "Response attempt",
      spec_url: "spawned://chaos-response",
      work_queue: response_queue,
      stage_name: "done",
      status: :completed,
      parent: parent,
      metadata: { "response_outcome_artifact_id" => "artifact-1" }
    )

    Engine::TransitionManager.advance_waiting_parent(parent)

    expect(parent.reload.stage_name).to eq("evaluate_recovery")
    expect(parent).to be_pending
    expect(parent.transition_logs.last.details["children_count"]).to eq(1)
  end
end

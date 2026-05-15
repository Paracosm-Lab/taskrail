require "rails_helper"

RSpec.describe "post incident replay cookbook", type: :request do
  def create_fake_post_incident_replay_queue
    queue = WorkQueue.create!(
      name: "Post Incident Replay Fixture #{SecureRandom.hex(4)}",
      slug: "post-incident-replay-fixture-#{SecureRandom.hex(4)}",
      stages: %w[ingest_artifacts reconstruct_timeline analyze_root_cause evaluate_response draft_updates human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "ingest_artifacts", adapter_type: "fake", completion_criteria: ["artifacts_ingested"])
    queue.stage_configs.create!(stage_name: "reconstruct_timeline", adapter_type: "fake", completion_criteria: ["timeline_reconstructed"])
    queue.stage_configs.create!(stage_name: "analyze_root_cause", adapter_type: "fake", completion_criteria: ["root_cause_analyzed"])
    queue.stage_configs.create!(stage_name: "evaluate_response", adapter_type: "fake", completion_criteria: ["response_evaluated"])
    queue.stage_configs.create!(stage_name: "draft_updates", adapter_type: "fake", completion_criteria: ["updates_drafted"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_post_incident_replay_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Replay post-incident analysis", spec_url: "docs/specs/cookbook-post-incident-replay.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("incident_artifacts", "incident_timeline", "root_cause_analysis", "response_evaluation", "incident_updates")
  end
end

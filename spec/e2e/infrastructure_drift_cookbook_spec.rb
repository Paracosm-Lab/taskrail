require "rails_helper"

RSpec.describe "infrastructure drift cookbook", type: :request do
  def create_fake_infrastructure_drift_queue
    queue = WorkQueue.create!(
      name: "Infrastructure Drift Fixture #{SecureRandom.hex(4)}",
      slug: "infrastructure-drift-fixture-#{SecureRandom.hex(4)}",
      stages: %w[collect_configs diff_environments classify_drift draft_sync_plan human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "collect_configs", adapter_type: "fake", completion_criteria: ["configs_collected"])
    queue.stage_configs.create!(stage_name: "diff_environments", adapter_type: "fake", completion_criteria: ["diff_produced"])
    queue.stage_configs.create!(stage_name: "classify_drift", adapter_type: "fake", completion_criteria: ["drift_classified"])
    queue.stage_configs.create!(stage_name: "draft_sync_plan", adapter_type: "fake", completion_criteria: ["sync_planned"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_infrastructure_drift_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Detect infrastructure drift", spec_url: "docs/specs/cookbook-infrastructure-drift.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("environment_configs", "environment_diff", "drift_classification", "sync_plan")
  end
end

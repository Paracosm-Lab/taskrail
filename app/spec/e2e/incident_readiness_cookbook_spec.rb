require "rails_helper"

RSpec.describe "incident readiness cookbook", type: :request do
  def create_fake_incident_readiness_queue
    queue = WorkQueue.create!(
      name: "Incident Readiness Fixture #{SecureRandom.hex(4)}",
      slug: "incident-readiness-fixture-#{SecureRandom.hex(4)}",
      stages: %w[inventory_services score_readiness identify_gaps draft_improvements human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "inventory_services", adapter_type: "fake", completion_criteria: ["service_inventory_produced"])
    queue.stage_configs.create!(stage_name: "score_readiness", adapter_type: "fake", completion_criteria: ["readiness_scored"])
    queue.stage_configs.create!(stage_name: "identify_gaps", adapter_type: "fake", completion_criteria: ["gaps_identified"])
    queue.stage_configs.create!(stage_name: "draft_improvements", adapter_type: "fake", completion_criteria: ["improvements_drafted"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_incident_readiness_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Assess incident readiness", spec_url: "docs/specs/cookbook-incident-readiness.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("service_inventory", "readiness_scores", "gap_analysis", "improvement_drafts")
  end
end

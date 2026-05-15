require "rails_helper"

RSpec.describe "job observability cookbook", type: :request do
  def create_fake_job_observability_queue
    queue = WorkQueue.create!(
      name: "Job Observability Fixture #{SecureRandom.hex(4)}",
      slug: "job-observability-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_job_classes assess_observability draft_fixes run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_job_classes", adapter_type: "fake", completion_criteria: ["job_inventory_produced"])
    queue.stage_configs.create!(stage_name: "assess_observability", adapter_type: "fake", completion_criteria: ["observability_assessed"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake", completion_criteria: ["fixes_drafted"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_job_observability_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Audit job observability", spec_url: "docs/specs/cookbook-job-observability.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("job_inventory", "observability_assessment", "fix_patches", "test_results")
  end
end

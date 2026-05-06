require "rails_helper"

RSpec.describe "test backfill cookbook", type: :request do
  def create_fake_test_backfill_queue
    queue = WorkQueue.create!(
      name: "Test Backfill Fixture #{SecureRandom.hex(4)}",
      slug: "test-backfill-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_coverage identify_gaps generate_tests run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_coverage", adapter_type: "fake", completion_criteria: ["coverage_map_produced"])
    queue.stage_configs.create!(stage_name: "identify_gaps", adapter_type: "fake", completion_criteria: ["test_plan_produced"])
    queue.stage_configs.create!(stage_name: "generate_tests", adapter_type: "fake", completion_criteria: ["tests_generated"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_test_backfill_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Backfill missing tests", spec_url: "docs/specs/cookbook-test-backfill.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("coverage_map", "test_plan", "integration_specs", "test_results")
  end
end

require "rails_helper"

RSpec.describe "query health cookbook", type: :request do
  def create_fake_query_health_queue
    queue = WorkQueue.create!(
      name: "Query Health Fixture #{SecureRandom.hex(4)}",
      slug: "query-health-fixture-#{SecureRandom.hex(4)}",
      stages: %w[collect_queries analyze_performance draft_fixes run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "collect_queries", adapter_type: "fake", completion_criteria: ["query_inventory_produced"])
    queue.stage_configs.create!(stage_name: "analyze_performance", adapter_type: "fake", completion_criteria: ["query_analyzed"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake", completion_criteria: ["query_fixes_drafted"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_query_health_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Audit query health", spec_url: "docs/specs/cookbook-query-health.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("query_inventory", "query_analysis", "query_patches", "test_results")
  end
end

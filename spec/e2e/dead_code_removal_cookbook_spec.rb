require "rails_helper"

RSpec.describe "dead code removal cookbook", type: :request do
  def create_fake_dead_code_removal_queue
    queue = WorkQueue.create!(
      name: "Dead Code Removal Fixture #{SecureRandom.hex(4)}",
      slug: "dead-code-removal-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_references verify_unused draft_removals run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_references", adapter_type: "fake", completion_criteria: ["candidates_identified"])
    queue.stage_configs.create!(stage_name: "verify_unused", adapter_type: "fake", completion_criteria: ["removals_verified"])
    queue.stage_configs.create!(stage_name: "draft_removals", adapter_type: "fake", completion_criteria: ["removals_drafted"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_dead_code_removal_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Remove dead code", spec_url: "docs/specs/cookbook-dead-code-removal.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("removal_candidates", "verified_removals", "removal_patches", "test_results")
  end
end

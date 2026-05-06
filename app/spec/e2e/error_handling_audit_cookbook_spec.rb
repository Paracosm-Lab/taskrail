require "rails_helper"

RSpec.describe "error handling audit cookbook", type: :request do
  def create_fake_error_handling_audit_queue
    queue = WorkQueue.create!(
      name: "Error Handling Audit Fixture #{SecureRandom.hex(4)}",
      slug: "error-handling-audit-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_error_handling classify_severity draft_fixes run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_error_handling", adapter_type: "fake", completion_criteria: ["error_patterns_found"])
    queue.stage_configs.create!(stage_name: "classify_severity", adapter_type: "fake", completion_criteria: ["severity_classified"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake", completion_criteria: ["fixes_drafted"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_error_handling_audit_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Audit error handling", spec_url: "docs/specs/cookbook-error-handling-audit.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("error_patterns", "severity_report", "fix_patches", "test_results")
  end
end

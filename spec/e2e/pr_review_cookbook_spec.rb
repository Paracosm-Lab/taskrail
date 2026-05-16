require "rails_helper"

RSpec.describe "PR review cookbook", type: :request do
  def create_fake_pr_review_queue
    queue = WorkQueue.create!(
      name: "PR Review Fixture #{SecureRandom.hex(4)}",
      slug: "pr-review-fixture-#{SecureRandom.hex(4)}",
      stages: %w[run_checks security_scan coverage_check architectural_review human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "run_checks", adapter_type: "fake", completion_criteria: ["checks_passed"])
    queue.stage_configs.create!(stage_name: "security_scan", adapter_type: "fake", completion_criteria: ["security_reviewed"])
    queue.stage_configs.create!(stage_name: "coverage_check", adapter_type: "fake", completion_criteria: ["coverage_checked"])
    queue.stage_configs.create!(stage_name: "architectural_review", adapter_type: "fake", completion_criteria: ["review_verdict"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_pr_review_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Review pull request", spec_url: "docs/specs/cookbook-15-pr-review-pipeline.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("check_results", "security_findings", "coverage_report")
    expect(work_item.reports.success.where(stage_name: "architectural_review").last.body).to include("verdict" => "approved")
  end
end

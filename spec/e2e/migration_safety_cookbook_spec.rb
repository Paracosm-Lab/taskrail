require "rails_helper"

RSpec.describe "migration safety cookbook", type: :request do
  def create_fake_migration_safety_queue
    queue = WorkQueue.create!(
      name: "Migration Safety Fixture #{SecureRandom.hex(4)}",
      slug: "migration-safety-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_impact enumerate_risks draft_rollback test_rollback draft_runbook human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_impact", adapter_type: "fake", completion_criteria: ["impact_mapped"])
    queue.stage_configs.create!(stage_name: "enumerate_risks", adapter_type: "fake", completion_criteria: ["risks_enumerated"])
    queue.stage_configs.create!(stage_name: "draft_rollback", adapter_type: "fake", completion_criteria: ["rollback_drafted"])
    queue.stage_configs.create!(stage_name: "test_rollback", adapter_type: "fake", completion_criteria: ["rollback_tested"])
    queue.stage_configs.create!(stage_name: "draft_runbook", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_migration_safety_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Assess migration safety", spec_url: "docs/specs/cookbook-migration-safety.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("impact_map", "risk_assessment", "rollback_plan", "rollback_test_results")
  end
end

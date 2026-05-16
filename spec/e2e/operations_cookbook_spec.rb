require "rails_helper"

RSpec.describe "operations cookbook", type: :request do
  def create_fake_operations_queue
    queue = WorkQueue.create!(
      name: "Operations Fixture #{SecureRandom.hex(4)}",
      slug: "operations-fixture-#{SecureRandom.hex(4)}",
      stages: %w[ingest_signals cluster_failures assess_instrumentation map_runbooks draft_runbook human_review staging_validation publish_runbook done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "ingest_signals", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "cluster_failures", adapter_type: "fake", completion_criteria: ["clusters_created"])
    queue.stage_configs.create!(stage_name: "assess_instrumentation", adapter_type: "fake", completion_criteria: ["assessment_complete"])
    queue.stage_configs.create!(stage_name: "map_runbooks", adapter_type: "fake", completion_criteria: ["runbook_mapped"])
    queue.stage_configs.create!(stage_name: "draft_runbook", adapter_type: "fake", completion_criteria: ["runbook_drafted"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "staging_validation", adapter_type: "fake", completion_criteria: ["validation_passed"])
    queue.stage_configs.create!(stage_name: "publish_runbook", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_operations_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Stabilize production incident", spec_url: "docs/specs/cookbook-operations.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    20.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("clusters", "instrumentation_assessment", "runbook_mapping", "runbook_draft")
    expect(work_item.reports.success.pluck(:stage_name)).to include("staging_validation", "publish_runbook")
  end
end

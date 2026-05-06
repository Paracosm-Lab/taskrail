require "rails_helper"

RSpec.describe "api docs sync cookbook", type: :request do
  def create_fake_api_docs_sync_queue
    queue = WorkQueue.create!(
      name: "API Docs Sync Fixture #{SecureRandom.hex(4)}",
      slug: "api-docs-sync-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_endpoints diff_existing_docs draft_documentation validate_examples human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_endpoints", adapter_type: "fake", completion_criteria: ["endpoint_inventory_produced"])
    queue.stage_configs.create!(stage_name: "diff_existing_docs", adapter_type: "fake", completion_criteria: ["docs_diff_produced"])
    queue.stage_configs.create!(stage_name: "draft_documentation", adapter_type: "fake", completion_criteria: ["docs_drafted"])
    queue.stage_configs.create!(stage_name: "validate_examples", adapter_type: "fake", completion_criteria: ["docs_validated"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_api_docs_sync_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Sync API docs", spec_url: "docs/specs/cookbook-api-docs-sync.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    # Report-based predicates: data lives in report body, not as artifact kinds
  end
end

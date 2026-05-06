require "rails_helper"

RSpec.describe "data integrity cookbook", type: :request do
  def create_fake_data_integrity_queue
    queue = WorkQueue.create!(
      name: "Data Integrity Fixture #{SecureRandom.hex(4)}",
      slug: "data-integrity-fixture-#{SecureRandom.hex(4)}",
      stages: %w[define_rules scan_violations assess_damage draft_repairs human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "define_rules", adapter_type: "fake", completion_criteria: ["rules_defined"])
    queue.stage_configs.create!(stage_name: "scan_violations", adapter_type: "fake", completion_criteria: ["violations_scanned"])
    queue.stage_configs.create!(stage_name: "assess_damage", adapter_type: "fake", completion_criteria: ["damage_assessed"])
    queue.stage_configs.create!(stage_name: "draft_repairs", adapter_type: "fake", completion_criteria: ["repairs_drafted"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_data_integrity_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Audit data integrity", spec_url: "docs/specs/cookbook-data-integrity.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("integrity_rules", "violation_report", "damage_assessment", "repair_scripts")
  end
end

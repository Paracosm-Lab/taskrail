require "rails_helper"

RSpec.describe "credential rotation cookbook", type: :request do
  def create_fake_credential_rotation_queue
    queue = WorkQueue.create!(
      name: "Credential Rotation Fixture #{SecureRandom.hex(4)}",
      slug: "credential-rotation-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_secrets map_dependencies assess_risk draft_rotation_plan human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_secrets", adapter_type: "fake", completion_criteria: ["secrets_scanned"])
    queue.stage_configs.create!(stage_name: "map_dependencies", adapter_type: "fake", completion_criteria: ["dependencies_mapped"])
    queue.stage_configs.create!(stage_name: "assess_risk", adapter_type: "fake", completion_criteria: ["risk_assessed"])
    queue.stage_configs.create!(stage_name: "draft_rotation_plan", adapter_type: "fake", completion_criteria: ["rotation_planned"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_credential_rotation_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Rotate credentials", spec_url: "docs/specs/cookbook-credential-rotation.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("secret_inventory", "dependency_map", "risk_assessment", "rotation_plan")
  end
end

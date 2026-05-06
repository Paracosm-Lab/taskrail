require "rails_helper"

RSpec.describe "chaos response cookbook", type: :request do
  def create_fake_chaos_response_queue
    queue = WorkQueue.create!(
      name: "Chaos Response Fixture #{SecureRandom.hex(4)}",
      slug: "chaos-response-fixture-#{SecureRandom.hex(4)}",
      stages: %w[detect_alerts diagnose_failure select_runbook execute_runbook verify_recovery report_outcome done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "detect_alerts", adapter_type: "fake", completion_criteria: ["alerts_detected"])
    queue.stage_configs.create!(stage_name: "diagnose_failure", adapter_type: "fake", completion_criteria: ["diagnosis_produced"])
    queue.stage_configs.create!(stage_name: "select_runbook", adapter_type: "fake", completion_criteria: ["runbook_selected"])
    queue.stage_configs.create!(stage_name: "execute_runbook", adapter_type: "fake", completion_criteria: ["runbook_executed"])
    queue.stage_configs.create!(stage_name: "verify_recovery", adapter_type: "fake", completion_criteria: ["recovery_verified"])
    queue.stage_configs.create!(stage_name: "report_outcome", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_chaos_response_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Respond to chaos event", spec_url: "docs/specs/cookbook-chaos-response.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("detected_alerts", "diagnosis", "runbook_selection", "runbook_execution", "recovery_verification")
  end
end

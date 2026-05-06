require "rails_helper"

RSpec.describe "chaos monkey cookbook", type: :request do
  def create_fake_chaos_monkey_queue
    queue = WorkQueue.create!(
      name: "Chaos Monkey Fixture #{SecureRandom.hex(4)}",
      slug: "chaos-monkey-fixture-#{SecureRandom.hex(4)}",
      stages: %w[plan_disruption execute_disruption monitor_impact hold_for_response evaluate_recovery score_and_report done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "plan_disruption", adapter_type: "fake", completion_criteria: ["disruption_planned"])
    queue.stage_configs.create!(stage_name: "execute_disruption", adapter_type: "fake", completion_criteria: ["disruption_executed"])
    queue.stage_configs.create!(stage_name: "monitor_impact", adapter_type: "fake", completion_criteria: ["impact_observed"])
    queue.stage_configs.create!(stage_name: "hold_for_response", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "evaluate_recovery", adapter_type: "fake", completion_criteria: ["recovery_evaluated"])
    queue.stage_configs.create!(stage_name: "score_and_report", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = create_fake_chaos_monkey_queue
    post "/api/v1/work_items", params: { queue: queue.slug, title: "Run chaos experiment", spec_url: "docs/specs/cookbook-chaos-monkey.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("disruption_plan", "disruption_record", "impact_report", "recovery_evaluation")
  end
end

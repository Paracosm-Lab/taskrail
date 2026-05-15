require "rails_helper"

RSpec.describe "chaos cookbook queue seeds" do
  before do
    Rails.application.load_seed
  end

  it "seeds the chaos_monkey queue with every configured stage" do
    queue = WorkQueue.find_by!(slug: "chaos_monkey")

    expect(queue.name).to eq("Chaos Monkey")
    expect(queue.stages).to eq(%w[
      plan_disruption execute_disruption monitor_impact hold_for_response
      evaluate_recovery score_and_report done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to match_array(queue.stages)
  end

  it "seeds the chaos_response queue with every configured stage" do
    queue = WorkQueue.find_by!(slug: "chaos_response")

    expect(queue.name).to eq("Chaos Response")
    expect(queue.stages).to eq(%w[
      detect_alerts diagnose_failure select_runbook execute_runbook
      verify_recovery report_outcome done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to match_array(queue.stages)
  end

  it "resolves file prompts instead of persisting file URI literals" do
    queue = WorkQueue.find_by!(slug: "chaos_monkey")
    stage = queue.stage_configs.find_by!(stage_name: "plan_disruption")

    expect(stage.agent_prompt).to include("You are planning a safe staging-only chaos exercise")
    expect(stage.agent_prompt).not_to include("file://")
  end

  it "keeps docker compose adapter paths portable" do
    chaos_queue = WorkQueue.find_by!(slug: "chaos_monkey")
    response_queue = WorkQueue.find_by!(slug: "chaos_response")

    compose_configs = [
      chaos_queue.stage_configs.find_by!(stage_name: "execute_disruption"),
      response_queue.stage_configs.find_by!(stage_name: "execute_runbook")
    ].map(&:adapter_config)

    expect(compose_configs).to all(include("compose_file" => "spec/fixtures/chaos_staging/docker-compose.staging.yml"))
    expect(compose_configs).to all(satisfy { |config| config["working_directory"].blank? })
  end

  it "prevents the response diagnosis stage from reading the disruption plan" do
    queue = WorkQueue.find_by!(slug: "chaos_response")
    stage = queue.stage_configs.find_by!(stage_name: "diagnose_failure")

    expect(stage.allowed_skills).to include("read_sentry")
    expect(stage.forbidden_skills).to include("read_disruption_plan")
    expect(stage.forbidden_skills).to include("execute_staging")
  end

  it "uses cookbook-specific predicates from the source spec" do
    chaos_queue = WorkQueue.find_by!(slug: "chaos_monkey")
    response_queue = WorkQueue.find_by!(slug: "chaos_response")

    expect(chaos_queue.stage_configs.find_by!(stage_name: "plan_disruption").completion_criteria).to eq(["disruption_planned"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "execute_disruption").completion_criteria).to eq(["disruption_executed"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "monitor_impact").completion_criteria).to eq(["impact_observed"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "evaluate_recovery").completion_criteria).to eq(["recovery_evaluated"])
    expect(response_queue.stage_configs.find_by!(stage_name: "detect_alerts").completion_criteria).to eq(["alerts_detected"])
    expect(response_queue.stage_configs.find_by!(stage_name: "diagnose_failure").completion_criteria).to eq(["diagnosis_produced"])
    expect(response_queue.stage_configs.find_by!(stage_name: "select_runbook").completion_criteria).to eq(["runbook_selected"])
    expect(response_queue.stage_configs.find_by!(stage_name: "execute_runbook").completion_criteria).to eq(["runbook_executed"])
    expect(response_queue.stage_configs.find_by!(stage_name: "verify_recovery").completion_criteria).to eq(["recovery_verified"])
  end
end

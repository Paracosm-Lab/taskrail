require "rails_helper"

RSpec.describe "chaos monkey cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "chaos_monkey") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      plan_disruption
      execute_disruption
      monitor_impact
      hold_for_response
      evaluate_recovery
      score_and_report
      done
    ])
  end

  it "has correct adapter configs per stage" do
    plan = queue.stage_configs.find_by!(stage_name: "plan_disruption")
    expect(plan.adapter_type).to eq("inline_claude")
    expect(plan.model_override).to eq("claude-sonnet-4-20250514")
    expect(plan.completion_criteria).to eq(["disruption_planned"])

    execute = queue.stage_configs.find_by!(stage_name: "execute_disruption")
    expect(execute.adapter_type).to eq("docker_compose")
    expect(execute.model_override).to be_nil
    expect(execute.completion_criteria).to eq(["disruption_executed"])

    monitor = queue.stage_configs.find_by!(stage_name: "monitor_impact")
    expect(monitor.adapter_type).to eq("shell_script")
    expect(monitor.model_override).to be_nil
    expect(monitor.completion_criteria).to eq(["impact_observed"])

    hold = queue.stage_configs.find_by!(stage_name: "hold_for_response")
    expect(hold.adapter_type).to eq("fake")
    expect(hold.model_override).to be_nil
    expect(hold.completion_criteria).to eq(["report_present"])

    evaluate = queue.stage_configs.find_by!(stage_name: "evaluate_recovery")
    expect(evaluate.adapter_type).to eq("inline_claude")
    expect(evaluate.model_override).to eq("claude-sonnet-4-20250514")
    expect(evaluate.completion_criteria).to eq(["recovery_evaluated"])

    score = queue.stage_configs.find_by!(stage_name: "score_and_report")
    expect(score.adapter_type).to eq("inline_claude")
    expect(score.model_override).to eq("claude-sonnet-4-20250514")
    expect(score.completion_criteria).to eq(["report_present"])

    done = queue.stage_configs.find_by!(stage_name: "done")
    expect(done.adapter_type).to eq("fake")
    expect(done.model_override).to be_nil
    expect(done.completion_criteria).to eq(["report_present"])
  end

  it "has all completion criteria registered in the predicate registry" do
    all_criteria = queue.stage_configs.flat_map(&:completion_criteria).uniq
    all_criteria.each do |criterion|
      expect { Engine::PredicateRegistry.resolve(criterion) }.not_to raise_error
    end
  end

  it "has no absolute paths in the queue YAML" do
    yaml_content = File.read(Rails.root.join("config/queues/chaos_monkey.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

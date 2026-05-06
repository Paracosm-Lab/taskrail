require "rails_helper"

RSpec.describe "credential rotation cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "credential_rotation") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      scan_secrets
      map_dependencies
      assess_risk
      draft_rotation_plan
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    scan = queue.stage_configs.find_by!(stage_name: "scan_secrets")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.completion_criteria).to eq(["secrets_scanned"])

    map = queue.stage_configs.find_by!(stage_name: "map_dependencies")
    expect(map.adapter_type).to eq("inline_claude")
    expect(map.model_override).to eq("claude-sonnet-4-20250514")
    expect(map.completion_criteria).to eq(["dependencies_mapped"])

    risk = queue.stage_configs.find_by!(stage_name: "assess_risk")
    expect(risk.adapter_type).to eq("inline_claude")
    expect(risk.model_override).to eq("claude-sonnet-4-20250514")
    expect(risk.completion_criteria).to eq(["risk_assessed"])

    plan = queue.stage_configs.find_by!(stage_name: "draft_rotation_plan")
    expect(plan.adapter_type).to eq("inline_claude")
    expect(plan.model_override).to eq("claude-sonnet-4-20250514")
    expect(plan.completion_criteria).to eq(["rotation_planned"])

    human = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human.adapter_type).to eq("fake")
    expect(human.model_override).to be_nil
    expect(human.completion_criteria).to eq(["report_present"])

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
    yaml_content = File.read(Rails.root.join("config/queues/credential_rotation.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

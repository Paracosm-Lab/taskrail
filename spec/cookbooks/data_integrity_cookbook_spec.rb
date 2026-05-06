require "rails_helper"

RSpec.describe "data integrity cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "data_integrity") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      define_rules
      scan_violations
      assess_damage
      draft_repairs
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    define_rules = queue.stage_configs.find_by!(stage_name: "define_rules")
    expect(define_rules.adapter_type).to eq("inline_claude")
    expect(define_rules.model_override).to eq("claude-sonnet-4-20250514")
    expect(define_rules.completion_criteria).to eq(["rules_defined"])

    scan = queue.stage_configs.find_by!(stage_name: "scan_violations")
    expect(scan.adapter_type).to eq("shell_script")
    expect(scan.model_override).to be_nil
    expect(scan.completion_criteria).to eq(["violations_scanned"])

    assess = queue.stage_configs.find_by!(stage_name: "assess_damage")
    expect(assess.adapter_type).to eq("inline_claude")
    expect(assess.model_override).to eq("claude-sonnet-4-20250514")
    expect(assess.completion_criteria).to eq(["damage_assessed"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_repairs")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["repairs_drafted"])

    human = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human.adapter_type).to eq("fake")
    expect(human.completion_criteria).to eq(["report_present"])

    done = queue.stage_configs.find_by!(stage_name: "done")
    expect(done.adapter_type).to eq("fake")
    expect(done.completion_criteria).to eq(["report_present"])
  end

  it "has all completion criteria registered in the predicate registry" do
    all_criteria = queue.stage_configs.flat_map(&:completion_criteria).uniq
    all_criteria.each do |criterion|
      expect { Engine::PredicateRegistry.resolve(criterion) }.not_to raise_error
    end
  end

  it "has no absolute paths in the queue YAML" do
    yaml_content = File.read(Rails.root.join("config/queues/data_integrity.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

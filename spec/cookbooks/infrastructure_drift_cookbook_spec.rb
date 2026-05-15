require "rails_helper"

RSpec.describe "infrastructure drift cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "infrastructure_drift") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      collect_configs
      diff_environments
      classify_drift
      draft_sync_plan
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    collect = queue.stage_configs.find_by!(stage_name: "collect_configs")
    expect(collect.adapter_type).to eq("shell_script")
    expect(collect.model_override).to be_nil
    expect(collect.completion_criteria).to eq(["configs_collected"])

    diff = queue.stage_configs.find_by!(stage_name: "diff_environments")
    expect(diff.adapter_type).to eq("inline_claude")
    expect(diff.model_override).to eq("claude-haiku-4-5-20251001")
    expect(diff.completion_criteria).to eq(["diff_produced"])

    classify = queue.stage_configs.find_by!(stage_name: "classify_drift")
    expect(classify.adapter_type).to eq("inline_claude")
    expect(classify.model_override).to eq("claude-sonnet-4-20250514")
    expect(classify.completion_criteria).to eq(["drift_classified"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_sync_plan")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["sync_planned"])

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
    yaml_content = File.read(Rails.root.join("config/queues/infrastructure_drift.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

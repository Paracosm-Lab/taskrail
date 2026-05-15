require "rails_helper"

RSpec.describe "query health cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "query_health") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      collect_queries
      analyze_performance
      draft_fixes
      run_tests
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    collect = queue.stage_configs.find_by!(stage_name: "collect_queries")
    expect(collect.adapter_type).to eq("shell_script")
    expect(collect.completion_criteria).to eq(["query_inventory_produced"])

    analyze = queue.stage_configs.find_by!(stage_name: "analyze_performance")
    expect(analyze.adapter_type).to eq("inline_claude")
    expect(analyze.model_override).to eq("claude-sonnet-4-20250514")
    expect(analyze.completion_criteria).to eq(["query_analyzed"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["query_fixes_drafted"])

    run = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run.adapter_type).to eq("shell_script")
    expect(run.completion_criteria).to eq(["tests_passed"])

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
    yaml_content = File.read(Rails.root.join("config/queues/query_health.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

require "rails_helper"

RSpec.describe "dead code removal cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "dead_code_removal") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      scan_references
      verify_unused
      draft_removals
      run_tests
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    scan = queue.stage_configs.find_by!(stage_name: "scan_references")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.completion_criteria).to eq(["candidates_identified"])

    verify = queue.stage_configs.find_by!(stage_name: "verify_unused")
    expect(verify.adapter_type).to eq("inline_claude")
    expect(verify.model_override).to eq("claude-sonnet-4-20250514")
    expect(verify.completion_criteria).to eq(["removals_verified"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_removals")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["removals_drafted"])

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
    yaml_content = File.read(Rails.root.join("config/queues/dead_code_removal.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

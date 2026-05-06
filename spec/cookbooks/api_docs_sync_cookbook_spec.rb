require "rails_helper"

RSpec.describe "API docs sync cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "api_docs_sync") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      scan_endpoints
      diff_existing_docs
      draft_documentation
      validate_examples
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    scan = queue.stage_configs.find_by!(stage_name: "scan_endpoints")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.completion_criteria).to eq(["endpoint_inventory_produced"])

    diff = queue.stage_configs.find_by!(stage_name: "diff_existing_docs")
    expect(diff.adapter_type).to eq("inline_claude")
    expect(diff.model_override).to eq("claude-sonnet-4-20250514")
    expect(diff.completion_criteria).to eq(["docs_diff_produced"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_documentation")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["docs_drafted"])

    validate = queue.stage_configs.find_by!(stage_name: "validate_examples")
    expect(validate.adapter_type).to eq("shell_script")
    expect(validate.completion_criteria).to eq(["docs_validated"])

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
    yaml_content = File.read(Rails.root.join("config/queues/api_docs_sync.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

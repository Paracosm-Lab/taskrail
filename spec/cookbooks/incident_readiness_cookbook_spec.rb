require "rails_helper"

RSpec.describe "incident readiness cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "incident_readiness") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      inventory_services
      score_readiness
      identify_gaps
      draft_improvements
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    inventory = queue.stage_configs.find_by!(stage_name: "inventory_services")
    expect(inventory.adapter_type).to eq("inline_claude")
    expect(inventory.model_override).to eq("claude-haiku-4-5-20251001")
    expect(inventory.completion_criteria).to eq(["service_inventory_produced"])

    score = queue.stage_configs.find_by!(stage_name: "score_readiness")
    expect(score.adapter_type).to eq("inline_claude")
    expect(score.model_override).to eq("claude-sonnet-4-20250514")
    expect(score.completion_criteria).to eq(["readiness_scored"])

    gaps = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(gaps.adapter_type).to eq("inline_claude")
    expect(gaps.model_override).to eq("claude-sonnet-4-20250514")
    expect(gaps.completion_criteria).to eq(["gaps_identified"])

    drafts = queue.stage_configs.find_by!(stage_name: "draft_improvements")
    expect(drafts.adapter_type).to eq("inline_claude")
    expect(drafts.model_override).to eq("claude-sonnet-4-20250514")
    expect(drafts.completion_criteria).to eq(["improvements_drafted"])

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
    yaml_content = File.read(Rails.root.join("config/queues/incident_readiness.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

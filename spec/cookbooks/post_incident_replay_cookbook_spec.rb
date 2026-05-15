require "rails_helper"

RSpec.describe "post incident replay cookbook" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "post_incident_replay") }

  it "loads with correct stages" do
    expect(queue.stages).to eq(%w[
      ingest_artifacts
      reconstruct_timeline
      analyze_root_cause
      evaluate_response
      draft_updates
      human_review
      done
    ])
  end

  it "has correct adapter configs per stage" do
    ingest = queue.stage_configs.find_by!(stage_name: "ingest_artifacts")
    expect(ingest.adapter_type).to eq("inline_claude")
    expect(ingest.model_override).to eq("claude-haiku-4-5-20251001")
    expect(ingest.completion_criteria).to eq(["artifacts_ingested"])

    timeline = queue.stage_configs.find_by!(stage_name: "reconstruct_timeline")
    expect(timeline.adapter_type).to eq("inline_claude")
    expect(timeline.model_override).to eq("claude-sonnet-4-20250514")
    expect(timeline.completion_criteria).to eq(["timeline_reconstructed"])

    root_cause = queue.stage_configs.find_by!(stage_name: "analyze_root_cause")
    expect(root_cause.adapter_type).to eq("inline_claude")
    expect(root_cause.model_override).to eq("claude-sonnet-4-20250514")
    expect(root_cause.completion_criteria).to eq(["root_cause_analyzed"])

    evaluate = queue.stage_configs.find_by!(stage_name: "evaluate_response")
    expect(evaluate.adapter_type).to eq("inline_claude")
    expect(evaluate.model_override).to eq("claude-sonnet-4-20250514")
    expect(evaluate.completion_criteria).to eq(["response_evaluated"])

    draft = queue.stage_configs.find_by!(stage_name: "draft_updates")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.model_override).to eq("claude-sonnet-4-20250514")
    expect(draft.completion_criteria).to eq(["updates_drafted"])

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
    yaml_content = File.read(Rails.root.join("config/queues/post_incident_replay.yml"))
    expect(yaml_content).not_to include("/Users/")
    expect(yaml_content).not_to include("/home/")
    expect(yaml_content).not_to include(Rails.root.to_s)
  end
end

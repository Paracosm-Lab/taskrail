require "rails_helper"

RSpec.describe "review regression" do
  it "moves review failures back to build with feedback" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done], config: { "max_regression_loops" => 3 })
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "review", completion_criteria: ["review_verdict"])
    work_item = WorkItem.create!(work_queue: queue, title: "Review thing", spec_url: "opaque spec", stage_name: "review", retry_count: 1, regression_count: 0, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "review", status: :failure, body: { "verdict" => "request_changes", "feedback" => "Extract service object" })

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("build")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.regression_count).to eq(1)
    expect(work_item.metadata["feedback"]).to include("Extract service object")
    expect(work_item.transition_logs.last.trigger).to eq("regression")
  end

  it "blocks when regression loop budget is exhausted" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done], config: { "max_regression_loops" => 1 })
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "review", completion_criteria: ["review_verdict"])
    work_item = WorkItem.create!(work_queue: queue, title: "Review thing", spec_url: "opaque spec", stage_name: "review", regression_count: 1, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "review", status: :failure, body: { "verdict" => "request_changes", "feedback" => "Still wrong" })

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_blocked
    expect(work_item.metadata["blocked_reason"]).to include("regression loop budget exhausted")
    expect(work_item.metadata.fetch("escalation")).to include(
      "target" => "human",
      "stage_name" => "review",
      "retry_count" => 0,
      "human_action_required" => true
    )
    expect(work_item.metadata.dig("escalation", "reason")).to eq("regression loop budget exhausted")
    expect(work_item.transition_logs.last.trigger).to eq("blocked")
    expect(work_item.transition_logs.last.details).to include(
      "human_action_required" => true,
      "escalation_target" => "human"
    )
  end
  it "moves failed generated tests from run_tests back to generate_tests with failure feedback" do
    queue = WorkQueue.create!(
      name: "Test Backfill",
      slug: "test-backfill-#{SecureRandom.hex(4)}",
      stages: %w[scan_coverage identify_gaps generate_tests run_tests human_review done],
      config: { "max_regression_loops" => 3 }
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "run_tests", completion_criteria: ["tests_passed"])
    work_item = WorkItem.create!(work_queue: queue, title: "Backfill", spec_url: "opaque spec", stage_name: "run_tests", regression_count: 0, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "shell", status: :completed)
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "test_results",
      data: { "passed" => false, "output" => "expected Widget#reorder_message to return stock ok", "failures" => ["Widget#reorder_message"] }
    )

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("generate_tests")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.regression_count).to eq(1)
    expect(work_item.metadata["feedback"]).to include("expected Widget#reorder_message")
    expect(work_item.metadata["feedback"]).to include("Widget#reorder_message")
    expect(work_item.transition_logs.last.trigger).to eq("regression")
    expect(work_item.transition_logs.last.details).to include("regression_count" => 1)
  end

  it "blocks failed generated tests when regression loop budget is exhausted" do
    queue = WorkQueue.create!(
      name: "Test Backfill",
      slug: "test-backfill-#{SecureRandom.hex(4)}",
      stages: %w[scan_coverage identify_gaps generate_tests run_tests human_review done],
      config: { "max_regression_loops" => 1 }
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "run_tests", completion_criteria: ["tests_passed"])
    work_item = WorkItem.create!(work_queue: queue, title: "Backfill", spec_url: "opaque spec", stage_name: "run_tests", regression_count: 1, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "shell", status: :completed)
    Artifact.create!(claim: claim, work_item: work_item, kind: "test_results", data: { "passed" => false, "output" => "still failing" })

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_blocked
    expect(work_item.metadata["blocked_reason"]).to include("regression loop budget exhausted")
    expect(work_item.transition_logs.last.trigger).to eq("blocked")
  end
end

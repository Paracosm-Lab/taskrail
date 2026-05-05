require "rails_helper"

RSpec.describe "error handling audit workflow", type: :model do
  it "advances through audit stages using produced artifacts" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "error_handling_audit")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Audit bad error handling fixture",
      spec_url: "test/fixtures/apps/bad_error_handling",
      stage_name: "scan_error_handling",
      status: :pending
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: scan_claim,
      kind: "error_patterns",
      data: {
        "patterns" => [
          {
            "file" => "test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb",
            "line" => 12,
            "type" => "bare_rescue_with_puts",
            "code_snippet" => "rescue => e
    puts e.message",
            "severity_hint" => "high"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: scan_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "scan_error_handling")
    ).call
    expect(work_item.reload.stage_name).to eq("classify_severity")

    classify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: classify_claim,
      kind: "severity_report",
      data: {
        "findings" => [
          {
            "patterns" => ["bare_rescue_with_puts:test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb:12"],
            "severity" => "high",
            "blast_radius" => "user-facing controller",
            "data_risk" => "generic failure hides payment errors",
            "frequency" => "hot path",
            "recommendation" => "capture exception and log structured context"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: classify_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "classify_severity")
    ).call
    expect(work_item.reload.stage_name).to eq("draft_fixes")

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: draft_claim,
      kind: "fix_patches",
      data: {
        "patches" => [
          {
            "file" => "test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb",
            "original" => "rescue => e
    puts e.message",
            "replacement" => "rescue PaymentGateway::Error => e
    Rails.logger.error(event: 'payment_failed', error_class: e.class.name)",
            "finding_ref" => "bare_rescue_with_puts:test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb:12",
            "severity" => "high"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: draft_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "draft_fixes")
    ).call
    expect(work_item.reload.stage_name).to eq("run_tests")

    processed = Engine::Runner.new.call

    expect(processed).to eq(work_item)
    expect(work_item.reload.stage_name).to eq("human_review")
    test_results = work_item.artifacts.find_by!(kind: "test_results")
    expect(test_results.data["passed"]).to eq(true)
    expect(work_item.transition_logs.pluck(:to_stage)).to include(
      "classify_severity",
      "draft_fixes",
      "run_tests",
      "human_review"
    )
  end
end

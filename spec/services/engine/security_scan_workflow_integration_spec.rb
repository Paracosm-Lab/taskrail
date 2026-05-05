require "rails_helper"

RSpec.describe "security scan cookbook workflow" do
  before do
    load Rails.root.join("db/seeds.rb")
  end

  let(:queue) { WorkQueue.find_by!(slug: "security_scan") }
  let(:work_item) do
    WorkItem.create!(
      work_queue: queue,
      title: "Scan vulnerable fixture",
      spec_url: "test/fixtures/apps/vulnerable_security_app",
      stage_name: "scan_vulnerabilities"
    )
  end

  it "accepts the scan, severity, fix, test, and review artifacts expected by the cookbook" do
    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    vulnerability_artifact = Artifact.create!(
      work_item: work_item,
      claim: scan_claim,
      kind: "vulnerability_scan",
      data: {
        "vulnerabilities" => [
          { "category" => "injection", "file" => "app/controllers/orders_controller.rb", "line" => 5, "evidence" => "Order.where", "exploitability" => "easy", "severity" => "critical" },
          { "category" => "secrets", "file" => "app/services/legacy_exporter.rb", "line" => 2, "evidence" => "LEGACY_API_KEY", "exploitability" => "easy", "severity" => "high" },
          { "category" => "xss", "file" => "app/views/orders/show.html.erb", "line" => 2, "evidence" => "html_safe", "exploitability" => "moderate", "severity" => "high" }
        ]
      }
    )

    scan_result = Engine::PredicateRegistry.resolve("scan_completed").new(claim: scan_claim).call
    expect(scan_result).to be_passed
    expect(scan_result.evidence).to eq({ artifact_id: vulnerability_artifact.id, vulnerability_count: 3 })

    classify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    severity_artifact = Artifact.create!(
      work_item: work_item,
      claim: classify_claim,
      kind: "severity_report",
      data: {
        "findings" => [
          {
            "vulnerabilities" => ["orders_controller SQL injection"],
            "severity" => "critical",
            "blast_radius" => "all orders",
            "exploitability" => "easy",
            "recommendation" => "replace interpolated query with parameterized lookup"
          },
          {
            "vulnerabilities" => ["legacy API key"],
            "severity" => "high",
            "blast_radius" => "third-party account",
            "exploitability" => "easy",
            "recommendation" => "move to environment variable and rotate credential"
          }
        ],
        "false_positives_removed" => 1
      }
    )

    severity_result = Engine::PredicateRegistry.resolve("severity_classified").new(claim: classify_claim).call
    expect(severity_result).to be_passed
    expect(severity_result.evidence).to eq({ artifact_id: severity_artifact.id, finding_count: 2 })

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    patch_artifact = Artifact.create!(
      work_item: work_item,
      claim: draft_claim,
      kind: "fix_patches",
      data: {
        "patches" => [
          { "file" => "app/controllers/orders_controller.rb", "original" => "Order.where", "replacement" => "Order.find_by", "vulnerability_ref" => "orders_controller SQL injection", "severity" => "critical" },
          { "file" => "app/services/legacy_exporter.rb", "original" => "LEGACY_API_KEY", "replacement" => "ENV.fetch", "vulnerability_ref" => "legacy API key", "severity" => "high" }
        ],
        "spawn" => [
          { "queue" => "credential_rotation", "reason" => "hardcoded API key must be rotated" }
        ]
      }
    )

    fixes_result = Engine::PredicateRegistry.resolve("fixes_drafted").new(claim: draft_claim).call
    expect(fixes_result).to be_passed
    expect(fixes_result.evidence).to eq({ artifact_id: patch_artifact.id, patch_count: 2 })

    test_claim = Claim.create!(work_item: work_item, agent_type: "shell_script", status: "completed", started_at: Time.current)
    test_artifact = Artifact.create!(
      work_item: work_item,
      claim: test_claim,
      kind: "test_results",
      data: { "passed" => true, "command" => "bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb" }
    )

    tests_result = Engine::PredicateRegistry.resolve("tests_passed").new(claim: test_claim).call
    expect(tests_result).to be_passed
    expect(tests_result.evidence).to eq({ artifact_id: test_artifact.id })

    review_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: "completed", started_at: Time.current)
    report = Report.create!(work_item: work_item, claim: review_claim, stage_name: "human_review", status: "success", body: { "reviewer" => "security" })

    report_result = Engine::PredicateRegistry.resolve("report_present").new(claim: review_claim).call
    expect(report_result).to be_passed
    expect(report_result.evidence).to eq({ report_id: report.id })
  end
end

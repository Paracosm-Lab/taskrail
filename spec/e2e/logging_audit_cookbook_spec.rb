require "rails_helper"

RSpec.describe "logging audit cookbook", type: :request do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/bad_logging") }

  it "provides the configured logging_audit queue with docker-friendly shell validation" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "logging_audit")

    expect(queue.stages).to eq(%w[
      scan_log_statements
      assess_quality
      draft_standard
      draft_fixes
      run_tests
      human_review
      done
    ])

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands")).to include(
      include(
        "name" => "logging audit cookbook e2e",
        "command" => "bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb",
        "artifact" => "test_results"
      )
    )
  end

  it "resolves every inline Claude prompt from repo-relative file paths" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "logging_audit")
    inline_stages = %w[scan_log_statements assess_quality draft_standard draft_fixes]

    inline_stages.each do |stage_name|
      stage = queue.stage_configs.find_by!(stage_name: stage_name)
      expect(stage.agent_prompt).to be_present
      expect(stage.agent_prompt).not_to start_with("file://")
      expect(stage.agent_prompt).to include("# Logging")
    end
  end

  it "contains fixture files for bad, missing, and good logging patterns" do
    expect(fixture_root.join("app/controllers/orders_controller.rb").read).to include("puts params.inspect")
    expect(fixture_root.join("app/jobs/process_user_job.rb").read).to include('Rails.logger.info "processing user"')
    expect(fixture_root.join("app/services/structured_payment_logger.rb").read).to include("payment_authorized")
    expect(fixture_root.join("app/services/structured_payment_logger.rb").read).to include("request_id")
    expect(fixture_root.join("app/services/payment_error_handler.rb").read).to include("Rails.logger.error error.message")

    critical_path = fixture_root.join("app/services/critical_account_reconciler.rb").read
    expect(critical_path).to include("reconcile!")
    expect(critical_path).not_to include("Rails.logger")
    expect(critical_path).not_to include("puts")
  end

  it "can satisfy the logging audit predicates with expected artifact kinds" do
    queue = WorkQueue.create!(
      name: "Logging Audit Predicate Flow #{SecureRandom.hex(4)}",
      slug: "logging-audit-predicate-flow-#{SecureRandom.hex(4)}",
      stages: %w[scan_log_statements assess_quality draft_standard done]
    )
    item = WorkItem.create!(title: "Audit fixture logging", spec_url: fixture_root.to_s, work_queue: queue, stage_name: "scan_log_statements")

    scan_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    log_inventory = Artifact.create!(
      work_item: item,
      claim: scan_claim,
      kind: "log_inventory",
      data: {
        "statements" => [
          { "file" => "app/controllers/orders_controller.rb", "line" => 3, "logger" => "puts", "level" => "unknown", "format" => "debug_output", "content" => "params.inspect", "context_present" => false }
        ],
        "summary" => { "total" => 1, "by_format" => { "debug_output" => 1 }, "by_level" => { "unknown" => 1 }, "by_service" => { "bad_logging" => 1 } }
      }
    )
    scan_result = Engine::Predicates::LogInventoryProduced.new(claim: scan_claim).call
    expect(scan_result).to be_passed
    expect(scan_result.evidence).to eq({ artifact_id: log_inventory.id })

    assess_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    assessment = Artifact.create!(
      work_item: item,
      claim: assess_claim,
      kind: "logging_assessment",
      data: { "best_patterns" => [], "worst_offenders" => [], "scores_by_file" => {}, "recommended_standard" => {} }
    )
    assess_result = Engine::Predicates::LoggingAssessed.new(claim: assess_claim).call
    expect(assess_result).to be_passed
    expect(assess_result.evidence).to eq({ artifact_id: assessment.id })

    standard_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    standard = Artifact.create!(
      work_item: item,
      claim: standard_claim,
      kind: "logging_standard",
      data: { "standard" => { "format" => "structured_json" } }
    )
    standard_result = Engine::Predicates::StandardDrafted.new(claim: standard_claim).call
    expect(standard_result).to be_passed
    expect(standard_result.evidence).to eq({ artifact_id: standard.id })
  end

  it "keeps queue YAML portable and references only repo-relative prompt files" do
    yaml_path = Rails.root.join("config/queues/logging_audit.yml")
    yaml = yaml_path.read

    expect(yaml).not_to include(Rails.root.to_s)
    expect(yaml).not_to include("/Users/")
    expect(yaml).not_to include("file:///")
    expect(yaml.scan(/file:\/\/prompts\/logging_[a-z_]+\.md/).uniq).to contain_exactly(
      "file://prompts/logging_scan_statements.md",
      "file://prompts/logging_assess_quality.md",
      "file://prompts/logging_draft_standard.md",
      "file://prompts/logging_draft_fixes.md"
    )
  end

  it "drives a work item through all stages using the fake adapter" do
    queue = WorkQueue.create!(
      name: "Logging Audit Fake Fixture #{SecureRandom.hex(4)}",
      slug: "logging-audit-fake-fixture-#{SecureRandom.hex(4)}",
      stages: %w[scan_log_statements assess_quality draft_standard draft_fixes run_tests human_review done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )
    queue.stage_configs.create!(stage_name: "scan_log_statements", adapter_type: "fake", completion_criteria: ["log_inventory_produced"])
    queue.stage_configs.create!(stage_name: "assess_quality", adapter_type: "fake", completion_criteria: ["logging_assessed"])
    queue.stage_configs.create!(stage_name: "draft_standard", adapter_type: "fake", completion_criteria: ["standard_drafted"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake", completion_criteria: ["fixes_drafted"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "human_review", adapter_type: "fake", completion_criteria: ["report_present"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])

    post "/api/v1/work_items", params: { queue: queue.slug, title: "Audit logging consistency", spec_url: "docs/specs/cookbook-06-logging-consistency-audit.md" }
    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending

    15.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.artifacts.pluck(:kind)).to include("log_inventory", "logging_assessment", "logging_standard", "fix_patches", "test_results")
  end

  it "covers the source cookbook spec stages, artifacts, and predicates" do
    source_spec = Rails.root.join("docs/specs/cookbook-06-logging-consistency-audit.md").read
    queue_yaml = Rails.root.join("config/queues/logging_audit.yml").read

    %w[
      scan_log_statements
      assess_quality
      draft_standard
      draft_fixes
      run_tests
      human_review
      done
      log_inventory
      logging_assessment
      logging_standard
      log_patches
      log_inventory_produced
      logging_assessed
      standard_drafted
    ].each do |required_term|
      expect(source_spec).to include(required_term)
      expect(queue_yaml).to include(required_term)
    end
  end
end

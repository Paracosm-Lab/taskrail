require "rails_helper"

RSpec.describe "development queue seed" do
  it "creates the development queue and stage configs" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development")
    expect(queue.stages).to eq(%w[intake decompose build test review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly("intake", "decompose", "build", "test", "review", "done")

    build = queue.stage_configs.find_by!(stage_name: "build")
    expect(build.allowed_skills).to include("clone_repo", "create_branch", "edit_files", "run_tests")
    expect(build.forbidden_skills).to include("deploy", "merge_main", "mutate_database")
    expect(build.adapter_type).to eq("fake")

    test_stage = queue.stage_configs.find_by!(stage_name: "test")
    expect(test_stage.completion_criteria).to eq(%w[tests_passed lint_clean coverage_not_decreased])
    expect(test_stage.adapter_config).to eq({})
  end

  it "seeds the shell-backed development queue" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development-shell")
    test_stage = queue.stage_configs.find_by!(stage_name: "test")

    expect(test_stage.adapter_type).to eq("shell_script")
    expect(test_stage.adapter_config["commands"].map { |command| command["artifact"] }).to include("test_results", "lint", "coverage")
  end

  it "seeds the claude-backed development queue" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development-claude")
    expect(queue.stage_configs.find_by!(stage_name: "intake").adapter_type).to eq("inline_claude")
    expect(queue.stage_configs.find_by!(stage_name: "decompose").adapter_type).to eq("inline_claude")
    expect(queue.stage_configs.find_by!(stage_name: "review").adapter_type).to eq("inline_claude")
    expect(queue.stage_configs.find_by!(stage_name: "test").adapter_type).to eq("shell_script")

    development = WorkQueue.find_by!(slug: "development")
    expect(development.stage_configs.find_by!(stage_name: "intake").adapter_type).to eq("fake")
  end

  it "seeds the codex-backed development queue" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development-codex")
    expect(queue.stage_configs.find_by!(stage_name: "intake").adapter_type).to eq("inline_claude")
    expect(queue.stage_configs.find_by!(stage_name: "decompose").adapter_type).to eq("inline_claude")
    build = queue.stage_configs.find_by!(stage_name: "build")
    expect(build.adapter_type).to eq("codex")
    expect(build.adapter_config["command"]).to eq("codex")
    expect(build.adapter_config["poll_command"]).to eq("codex")
    expect(queue.stage_configs.find_by!(stage_name: "test").adapter_type).to eq("shell_script")
    expect(queue.stage_configs.find_by!(stage_name: "review").adapter_type).to eq("inline_claude")

    development = WorkQueue.find_by!(slug: "development")
    expect(development.stage_configs.find_by!(stage_name: "build").adapter_type).to eq("fake")
  end

  it "seeds the feature development cookbook queue with resolved prompt files and portable adapters" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development-codex")
    expect(queue.name).to eq("Development Codex")
    expect(queue.stages).to eq(%w[intake decompose build test review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 3,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 3
    )

    intake = queue.stage_configs.find_by!(stage_name: "intake")
    expect(intake.adapter_type).to eq("inline_claude")
    expect(intake.allowed_skills).to eq(%w[read_spec classify tag_work_item])
    expect(intake.completion_criteria).to eq(["report_present"])
    expect(intake.agent_prompt).to include("# Development Intake")
    expect(intake.agent_prompt).to include("classify")
    expect(intake.agent_prompt).not_to start_with("file://")

    decompose = queue.stage_configs.find_by!(stage_name: "decompose")
    expect(decompose.adapter_type).to eq("inline_claude")
    expect(decompose.allowed_skills).to eq(%w[read_spec create_child_items define_acceptance_criteria])
    expect(decompose.agent_prompt).to include("# Development Decompose")
    expect(decompose.agent_prompt).to include("children")
    expect(decompose.agent_prompt).not_to start_with("file://")

    build = queue.stage_configs.find_by!(stage_name: "build")
    expect(build.adapter_type).to eq("codex")
    expect(build.allowed_skills).to eq(%w[clone_repo create_branch edit_files run_tests])
    expect(build.forbidden_skills).to include("deploy", "merge_main", "mutate_database")
    expect(build.completion_criteria).to eq(%w[branch_created report_present])
    expect(build.agent_prompt).to include("# Development Build")
    expect(build.agent_prompt).to include("branch")
    expect(build.adapter_config).to include(
      "command" => "codex",
      "poll_command" => "codex"
    )
    expect(build.adapter_config).not_to have_key("working_directory")

    test_stage = queue.stage_configs.find_by!(stage_name: "test")
    expect(test_stage.adapter_type).to eq("shell_script")
    expect(test_stage.allowed_skills).to eq(%w[run_tests run_linter run_coverage])
    expect(test_stage.forbidden_skills).to include("edit_files")
    expect(test_stage.completion_criteria).to eq(%w[tests_passed lint_clean coverage_not_decreased])
    expect(test_stage.agent_prompt).to include("# Development Test")
    expect(test_stage.agent_prompt).not_to start_with("file://")
    expect(test_stage.adapter_config).not_to have_key("working_directory")
    expect(test_stage.adapter_config.fetch("commands").map { |command| command.fetch("artifact") }).to include("test_results", "lint", "coverage")

    review = queue.stage_configs.find_by!(stage_name: "review")
    expect(review.adapter_type).to eq("inline_claude")
    expect(review.max_retries).to eq(0)
    expect(review.allowed_skills).to eq(%w[read_diff read_spec approve request_changes])
    expect(review.completion_criteria).to eq(["review_verdict"])
    expect(review.agent_prompt).to include("# Development Review")
    expect(review.agent_prompt).to include("request_changes")
    expect(review.agent_prompt).not_to start_with("file://")

    done = queue.stage_configs.find_by!(stage_name: "done")
    expect(done.adapter_type).to eq("fake")
    expect(done.completion_criteria).to eq(["report_present"])
  end


  it "seeds the operations queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "operations")
    expect(queue.stages).to eq(%w[
      ingest_signals
      cluster_failures
      assess_instrumentation
      map_runbooks
      draft_runbook
      human_review
      staging_validation
      publish_runbook
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    ingest = queue.stage_configs.find_by!(stage_name: "ingest_signals")
    expect(ingest.adapter_type).to eq("inline_claude")
    expect(ingest.allowed_skills).to include("read_sentry", "query_logs")
    expect(ingest.forbidden_skills).to include("deploy_prod", "mutate_database", "execute_staging")
    expect(ingest.agent_prompt).to include("# Ops Ingest Signals")
    expect(ingest.agent_prompt).to include("operations ingestion agent")
    expect(ingest.agent_prompt).not_to start_with("file://")

    draft = queue.stage_configs.find_by!(stage_name: "draft_runbook")
    expect(draft.agent_prompt).to include("# Ops Draft Runbook")
    expect(draft.model_override).to eq("claude-opus-4-20250514")

    staging_validation = queue.stage_configs.find_by!(stage_name: "staging_validation")
    expect(staging_validation.adapter_type).to eq("docker_compose")
    expect(staging_validation.adapter_config["compose_file"]).to eq("docker-compose.dev.yml")
  end

  it "seeds the dead code removal cookbook queue with resolved portable prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "dead_code_removal")
    expect(queue.name).to eq("Dead Code Removal")
    expect(queue.stages).to eq(%w[scan_references verify_unused draft_removals run_tests human_review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_references")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["candidates_identified"])
    expect(scan.agent_prompt).to include("# Dead Code Scan References")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.agent_prompt).not_to include(Rails.root.to_s)
    expect(scan.adapter_config).to include(
      "output_artifact_kind" => "removal_candidates",
      "fixture_app" => "cookbooks/fixtures/apps/dead_code_app"
    )

    verify = queue.stage_configs.find_by!(stage_name: "verify_unused")
    expect(verify.model_override).to eq("claude-sonnet-4-20250514")
    expect(verify.completion_criteria).to eq(["removals_verified"])
    expect(verify.agent_prompt).to include("needs_investigation")
    expect(verify.adapter_config).to include(
      "output_artifact_kind" => "verified_removals",
      "input_artifact_kind" => "removal_candidates",
      "fixture_app" => "cookbooks/fixtures/apps/dead_code_app"
    )

    draft = queue.stage_configs.find_by!(stage_name: "draft_removals")
    expect(draft.completion_criteria).to eq(["removals_drafted"])
    expect(draft.agent_prompt).to include("safe_to_remove")
    expect(draft.adapter_config).to include(
      "output_artifact_kind" => "removal_patches",
      "input_artifact_kind" => "verified_removals",
      "fixture_app" => "cookbooks/fixtures/apps/dead_code_app"
    )

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to include("run_tests")
    expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).to include("output_artifact_kind" => "test_results")
    expect(run_tests.adapter_config).not_to have_key("working_directory")

    serialized_queue = Rails.root.join("config/queues/dead_code_removal.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).to include("file://cookbooks/prompts/dead_code_removal/scan_references.md")
  end


  it "seeds the error handling audit queue with resolved portable prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "error_handling_audit")
    expect(queue.name).to eq("Error Handling Audit")
    expect(queue.stages).to eq(%w[
      scan_error_handling
      classify_severity
      draft_fixes
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "default_timeout_seconds" => 600,
      "max_regression_loops" => 3
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_error_handling")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["error_patterns_found"])
    expect(scan.agent_prompt).to include("# Audit Scan Error Handling")
    expect(scan.agent_prompt).to include("error_patterns")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.agent_prompt).not_to include(Rails.root.to_s)
    expect(scan.adapter_config).to eq("output_artifact_kind" => "error_patterns")

    classify = queue.stage_configs.find_by!(stage_name: "classify_severity")
    expect(classify.adapter_type).to eq("inline_claude")
    expect(classify.model_override).to eq("claude-sonnet-4-20250514")
    expect(classify.completion_criteria).to eq(["severity_classified"])
    expect(classify.agent_prompt).to include("# Audit Classify Severity")
    expect(classify.adapter_config).to eq("output_artifact_kind" => "severity_report")

    draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.completion_criteria).to eq(["fixes_drafted"])
    expect(draft.agent_prompt).to include("# Audit Draft Fixes")
    expect(draft.adapter_config).to eq("output_artifact_kind" => "fix_patches")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to include("run_tests")
    expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands").first).to include(
      "name" => "error handling audit fixture smoke",
      "artifact" => "test_results"
    )
    expect(run_tests.adapter_config.fetch("commands").first.fetch("command")).to include("test/fixtures/apps/bad_error_handling")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/error_handling_audit.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).not_to include("working_directory:")
    expect(serialized_queue).to include("file://prompts/audit_scan_error_handling.md")
  end

  it "seeds the api docs sync queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "api_docs_sync")
    expect(queue.name).to eq("API Documentation Sync")
    expect(queue.stages).to eq(%w[
      scan_endpoints
      diff_existing_docs
      draft_documentation
      validate_examples
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_endpoints")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["endpoint_inventory_produced"])
    expect(scan.agent_prompt).to include("# API Docs Scan Endpoints")
    expect(scan.agent_prompt).to include("endpoint_inventory")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.adapter_config).to eq("output_artifact_kind" => "endpoint_inventory")

    diff = queue.stage_configs.find_by!(stage_name: "diff_existing_docs")
    expect(diff.adapter_type).to eq("inline_claude")
    expect(diff.model_override).to eq("claude-sonnet-4-20250514")
    expect(diff.completion_criteria).to eq(["docs_diff_produced"])
    expect(diff.agent_prompt).to include("# API Docs Diff Existing Documentation")
    expect(diff.adapter_config).to eq("output_artifact_kind" => "docs_diff")

    draft = queue.stage_configs.find_by!(stage_name: "draft_documentation")
    expect(draft.completion_criteria).to eq(["docs_drafted"])
    expect(draft.agent_prompt).to include("# API Docs Draft Documentation")
    expect(draft.adapter_config).to eq("output_artifact_kind" => "draft_docs")

    validate = queue.stage_configs.find_by!(stage_name: "validate_examples")
    expect(validate.adapter_type).to eq("shell_script")
    expect(validate.completion_criteria).to eq(["docs_validated"])
    expect(validate.allowed_skills).to include("run_validation")
    expect(validate.adapter_config["output_artifact_kind"]).to eq("validation_results")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/api_docs_sync.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).not_to include("working_directory:")
    expect(serialized_queue).to include("file://prompts/docs_scan_endpoints.md")
  end

  it "seeds the background job observability queue with resolved portable prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "job_observability")
    expect(queue.name).to eq("Background Job Observability")
    expect(queue.stages).to eq(%w[scan_job_classes assess_observability draft_fixes run_tests human_review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_job_classes")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(%w[read_repo])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(%w[job_inventory_produced])
    expect(scan.agent_prompt).to include("# Job Observability: Scan Job Classes")
    expect(scan.agent_prompt).to include("job_inventory")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.agent_prompt).not_to include(Rails.root.to_s)
    expect(scan.adapter_config).to eq("output_artifact_kind" => "job_inventory")

    assess = queue.stage_configs.find_by!(stage_name: "assess_observability")
    expect(assess.adapter_type).to eq("inline_claude")
    expect(assess.model_override).to eq("claude-sonnet-4-20250514")
    expect(assess.completion_criteria).to eq(%w[observability_assessed])
    expect(assess.agent_prompt).to include("# Job Observability: Assess Observability")
    expect(assess.agent_prompt).to include("scorecard")
    expect(assess.adapter_config).to eq("output_artifact_kind" => "observability_assessment")

    draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.allowed_skills).to eq(%w[read_repo])
    expect(draft.forbidden_skills).to eq(%w[deploy])
    expect(draft.max_retries).to eq(2)
    expect(draft.completion_criteria).to eq(%w[fixes_drafted])
    expect(draft.agent_prompt).to include("# Job Observability: Draft Fixes")
    expect(draft.adapter_config).to eq("output_artifact_kind" => "job_patches")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(%w[run_tests])
    expect(run_tests.forbidden_skills).to i

... [OUTPUT TRUNCATED - 1881 chars omitted out of 51881 total] ...

", "deploy")
    expect(inventory.completion_criteria).to eq(["service_inventory_produced"])
    expect(inventory.agent_prompt).to include("# Readiness Inventory")
    expect(inventory.agent_prompt).to include("service inventory")
    expect(inventory.agent_prompt).not_to start_with("file://")
    expect(inventory.adapter_config).to eq("output_artifact_kind" => "service_inventory")

    score = queue.stage_configs.find_by!(stage_name: "score_readiness")
    expect(score.model_override).to eq("claude-sonnet-4-20250514")
    expect(score.completion_criteria).to eq(["readiness_scored"])
    expect(score.agent_prompt).to include("# Readiness Score")
    expect(score.adapter_config).to eq("output_artifact_kind" => "readiness_scores")

    gaps = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(gaps.completion_criteria).to eq(["gaps_identified"])
    expect(gaps.agent_prompt).to include("# Readiness Gaps")
    expect(gaps.adapter_config).to eq("output_artifact_kind" => "gap_analysis")

    drafts = queue.stage_configs.find_by!(stage_name: "draft_improvements")
    expect(drafts.completion_criteria).to eq(["improvements_drafted"])
    expect(drafts.forbidden_skills).to eq(["deploy"])
    expect(drafts.agent_prompt).to include("# Readiness Draft Improvements")
    expect(drafts.adapter_config).to eq("output_artifact_kind" => "improvement_drafts")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(["report_present"])
    expect(human_review.timeout_seconds).to eq(86_400)
  end

  it "seeds the api docs sync queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "api_docs_sync")
    expect(queue.name).to eq("API Documentation Sync")
    expect(queue.stages).to eq(%w[
      scan_endpoints
      diff_existing_docs
      draft_documentation
      validate_examples
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_endpoints")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["endpoint_inventory_produced"])
    expect(scan.agent_prompt).to include("# API Docs Scan Endpoints")
    expect(scan.agent_prompt).to include("endpoint_inventory")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.adapter_config).to eq("output_artifact_kind" => "endpoint_inventory")

    diff = queue.stage_configs.find_by!(stage_name: "diff_existing_docs")
    expect(diff.adapter_type).to eq("inline_claude")
    expect(diff.model_override).to eq("claude-sonnet-4-20250514")
    expect(diff.completion_criteria).to eq(["docs_diff_produced"])
    expect(diff.agent_prompt).to include("# API Docs Diff Existing Documentation")
    expect(diff.adapter_config).to eq("output_artifact_kind" => "docs_diff")

    draft = queue.stage_configs.find_by!(stage_name: "draft_documentation")
    expect(draft.completion_criteria).to eq(["docs_drafted"])
    expect(draft.agent_prompt).to include("# API Docs Draft Documentation")
    expect(draft.adapter_config).to eq("output_artifact_kind" => "draft_docs")

    validate = queue.stage_configs.find_by!(stage_name: "validate_examples")
    expect(validate.adapter_type).to eq("shell_script")
    expect(validate.completion_criteria).to eq(["docs_validated"])
    expect(validate.allowed_skills).to include("run_validation")
    expect(validate.adapter_config["output_artifact_kind"]).to eq("validation_results")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/api_docs_sync.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).not_to include("working_directory:")
    expect(serialized_queue).to include("file://prompts/docs_scan_endpoints.md")
  end

  it "seeds the background job observability queue with resolved portable prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "job_observability")
    expect(queue.name).to eq("Background Job Observability")
    expect(queue.stages).to eq(%w[scan_job_classes assess_observability draft_fixes run_tests human_review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_job_classes")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(%w[read_repo])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(%w[job_inventory_produced])
    expect(scan.agent_prompt).to include("# Job Observability: Scan Job Classes")
    expect(scan.agent_prompt).to include("job_inventory")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.agent_prompt).not_to include(Rails.root.to_s)
    expect(scan.adapter_config).to eq("output_artifact_kind" => "job_inventory")

    assess = queue.stage_configs.find_by!(stage_name: "assess_observability")
    expect(assess.adapter_type).to eq("inline_claude")
    expect(assess.model_override).to eq("claude-sonnet-4-20250514")
    expect(assess.completion_criteria).to eq(%w[observability_assessed])
    expect(assess.agent_prompt).to include("# Job Observability: Assess Observability")
    expect(assess.agent_prompt).to include("scorecard")
    expect(assess.adapter_config).to eq("output_artifact_kind" => "observability_assessment")

    draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.allowed_skills).to eq(%w[read_repo])
    expect(draft.forbidden_skills).to eq(%w[deploy])
    expect(draft.max_retries).to eq(2)
    expect(draft.completion_criteria).to eq(%w[fixes_drafted])
    expect(draft.agent_prompt).to include("# Job Observability: Draft Fixes")
    expect(draft.adapter_config).to eq("output_artifact_kind" => "job_patches")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(%w[run_tests])
    expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
    expect(run_tests.completion_criteria).to eq(%w[tests_passed])
    expect(run_tests.timeout_seconds).to eq(600)
    expect(run_tests.adapter_config.fetch("commands").first.fetch("command")).to include("bundle exec rspec")
    expect(run_tests.adapter_config).not_to have_key("working_directory")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(%w[report_present])
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/job_observability.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).to include("file://prompts/jobs_scan_classes.md")
  end


  it "seeds the test coverage backfill cookbook queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "test_backfill")
    expect(queue.name).to eq("Test Coverage Backfill")
    expect(queue.stages).to eq(%w[
      scan_coverage
      identify_gaps
      generate_tests
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 3
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_coverage")
    expect(scan.adapter_type).to eq("shell_script")
    expect(scan.allowed_skills).to eq(["run_coverage"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["coverage_map_produced"])
    expect(scan.agent_prompt).to include("# Backfill Scan Coverage")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.adapter_config).to include("output_artifact_kind" => "coverage_map")
    expect(scan.adapter_config).not_to have_key("working_directory")

    identify = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(identify.adapter_type).to eq("inline_claude")
    expect(identify.model_override).to eq("claude-sonnet-4-20250514")
    expect(identify.allowed_skills).to eq(["read_repo"])
    expect(identify.completion_criteria).to eq(["test_plan_produced"])
    expect(identify.agent_prompt).to include("# Backfill Identify Gaps")
    expect(identify.adapter_config).to include("output_artifact_kind" => "test_plan")

    generate = queue.stage_configs.find_by!(stage_name: "generate_tests")
    expect(generate.adapter_type).to eq("inline_claude")
    expect(generate.model_override).to eq("claude-sonnet-4-20250514")
    expect(generate.allowed_skills).to eq(["read_repo"])
    expect(generate.forbidden_skills).to include("deploy")
    expect(generate.completion_criteria).to eq(["tests_generated"])
    expect(generate.agent_prompt).to include("# Backfill Generate Tests")
    expect(generate.adapter_config).to include("output_artifact_kind" => "generated_tests")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(["run_tests"])
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).to include("output_artifact_kind" => "test_results")
    expect(run_tests.adapter_config).not_to have_key("working_directory")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/test_backfill.yml").read
    expect(serialized_queue).to include("file://cookbooks/prompts/test_backfill/scan_coverage.md")
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
  end


  it "seeds the incident readiness queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "incident_readiness")
    expect(queue.name).to eq("Incident Readiness Scoring")
    expect(queue.stages).to eq(%w[
      inventory_services
      score_readiness
      identify_gaps
      draft_improvements
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 0
    )

    inventory = queue.stage_configs.find_by!(stage_name: "inventory_services")
    expect(inventory.adapter_type).to eq("inline_claude")
    expect(inventory.model_override).to eq("claude-haiku-4-5-20251001")
    expect(inventory.allowed_skills).to eq(["read_repo"])
    expect(inventory.forbidden_skills).to include("edit_files", "deploy")
    expect(inventory.completion_criteria).to eq(["service_inventory_produced"])
    expect(inventory.agent_prompt).to include("# Readiness Inventory")
    expect(inventory.agent_prompt).to include("service inventory")
    expect(inventory.agent_prompt).not_to start_with("file://")
    expect(inventory.adapter_config).to eq("output_artifact_kind" => "service_inventory")

    score = queue.stage_configs.find_by!(stage_name: "score_readiness")
    expect(score.model_override).to eq("claude-sonnet-4-20250514")
    expect(score.completion_criteria).to eq(["readiness_scored"])
    expect(score.agent_prompt).to include("# Readiness Score")
    expect(score.adapter_config).to eq("output_artifact_kind" => "readiness_scores")

    gaps = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(gaps.completion_criteria).to eq(["gaps_identified"])
    expect(gaps.agent_prompt).to include("# Readiness Gaps")
    expect(gaps.adapter_config).to eq("output_artifact_kind" => "gap_analysis")

    drafts = queue.stage_configs.find_by!(stage_name: "draft_improvements")
    expect(drafts.completion_criteria).to eq(["improvements_drafted"])
    expect(drafts.forbidden_skills).to eq(["deploy"])
    expect(drafts.agent_prompt).to include("# Readiness Draft Improvements")
    expect(drafts.adapter_config).to eq("output_artifact_kind" => "improvement_drafts")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(["report_present"])
    expect(human_review.timeout_seconds).to eq(86_400)
  end

  it "seeds the logging audit cookbook queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "logging_audit")
    expect(queue.name).to eq("Logging Consistency Audit")
    expect(queue.stages).to eq(%w[
      scan_log_statements
      assess_quality
      draft_standard
      draft_fixes
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_log_statements")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["log_inventory_produced"])
    expect(scan.adapter_config).to eq("output_artifact_kind" => "log_inventory")
    expect(scan.agent_prompt).to include("# Logging Scan Statements")
    expect(scan.agent_prompt).to include("log_inventory")
    expect(scan.agent_prompt).not_to start_with("file://")

    assess = queue.stage_configs.find_by!(stage_name: "assess_quality")
    expect(assess.adapter_type).to eq("inline_claude")
    expect(assess.model_override).to eq("claude-sonnet-4-20250514")
    expect(assess.completion_criteria).to eq(["logging_assessed"])
    expect(assess.adapter_config).to eq("output_artifact_kind" => "logging_assessment")
    expect(assess.agent_prompt).to include("# Logging Assess Quality")
    expect(assess.agent_prompt).not_to start_with("file://")

    standard = queue.stage_configs.find_by!(stage_name: "draft_standard")
    expect(standard.adapter_type).to eq("inline_claude")
    expect(standard.model_override).to eq("claude-sonnet-4-20250514")
    expect(standard.completion_criteria).to eq(["standard_drafted"])
    expect(standard.adapter_config).to eq("output_artifact_kind" => "logging_standard")
    expect(standard.agent_prompt).to include("# Logging Draft Standard")
    expect(standard.agent_prompt).not_to start_with("file://")

    fixes = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(fixes.adapter_type).to eq("inline_claude")
    expect(fixes.model_override).to eq("claude-sonnet-4-20250514")
    expect(fixes.allowed_skills).to eq(["read_repo"])
    expect(fixes.forbidden_skills).to include("deploy")
    expect(fixes.completion_criteria).to eq(["fixes_drafted"])
    expect(fixes.adapter_config).to eq("output_artifact_kind" => "log_patches")
    expect(fixes.agent_prompt).to include("# Logging Draft Fixes")
    expect(fixes.agent_prompt).not_to start_with("file://")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(["run_tests"])
    expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands")).to contain_exactly(
      include(
        "name" => "logging audit cookbook e2e",
        "artifact" => "test_results",
        "command" => "bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb"
      )
    )

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(["report_present"])
    expect(human_review.timeout_seconds).to eq(86_400)

    done = queue.stage_configs.find_by!(stage_name: "done")
    expect(done.adapter_type).to eq("fake")
    expect(done.completion_criteria).to eq(["report_present"])
  end

  it "seeds the test coverage backfill cookbook queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "test_backfill")
    expect(queue.name).to eq("Test Coverage Backfill")
    expect(queue.stages).to eq(%w[
      scan_coverage
      identify_gaps
      generate_tests
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 3
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_coverage")
    expect(scan.adapter_type).to eq("shell_script")
    expect(scan.allowed_skills).to eq(["run_coverage"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["coverage_map_produced"])
    expect(scan.agent_prompt).to include("# Backfill Scan Coverage")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.adapter_config).to include("output_artifact_kind" => "coverage_map")
    expect(scan.adapter_config).not_to have_key("working_directory")

    identify = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(identify.adapter_type).to eq("inline_claude")
    expect(identify.model_override).to eq("claude-sonnet-4-20250514")
    expect(identify.allowed_skills).to eq(["read_repo"])
    expect(identify.completion_criteria).to eq(["test_plan_produced"])
    expect(identify.agent_prompt).to include("# Backfill Identify Gaps")
    expect(identify.adapter_config).to include("output_artifact_kind" => "test_plan")

    generate = queue.stage_configs.find_by!(stage_name: "generate_tests")
    expect(generate.adapter_type).to eq("inline_claude")
    expect(generate.model_override).to eq("claude-sonnet-4-20250514")
    expect(generate.allowed_skills).to eq(["read_repo"])
    expect(generate.forbidden_skills).to include("deploy")
    expect(generate.completion_criteria).to eq(["tests_generated"])
    expect(generate.agent_prompt).to include("# Backfill Generate Tests")
    expect(generate.adapter_config).to include("output_artifact_kind" => "generated_tests")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(["run_tests"])
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).to include("output_artifact_kind" => "test_results")
    expect(run_tests.adapter_config).not_to have_key("working_directory")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/test_backfill.yml").read
    expect(serialized_queue).to include("file://cookbooks/prompts/test_backfill/scan_coverage.md")
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
  end

  it "seeds the credential rotation audit queue with resolved read-only prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "credential_rotation")
    expect(queue.name).to eq("Credential Rotation Audit")
    expect(queue.stages).to eq(%w[scan_secrets map_dependencies assess_risk draft_rotation_plan human_review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 0
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_secrets")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
    expect(scan.completion_criteria).to eq(["secrets_scanned"])
    expect(scan.adapter_config).to include("output_artifact_kind" => "secret_inventory", "fixture_app" => "test/fixtures/apps/leaky_credentials", "read_only" => true)
    expect(scan.agent_prompt).to include("# Credential Scan", "secret_inventory", "READ-ONLY")
    expect(scan.agent_prompt).not_to start_with("file://")

    dependencies = queue.stage_configs.find_by!(stage_name: "map_dependencies")
    expect(dependencies.model_override).to eq("claude-sonnet-4-20250514")
    expect(dependencies.completion_criteria).to eq(["dependencies_mapped"])
    expect(dependencies.adapter_config).to include("input_artifact_kind" => "secret_inventory", "output_artifact_kind" => "dependency_map", "fixture_app" => "test/fixtures/apps/leaky_credentials", "read_only" => true)
    expect(dependencies.agent_prompt).to include("# Credential Dependencies", "dependency_map")

    risk = queue.stage_configs.find_by!(stage_name: "assess_risk")
    expect(risk.completion_criteria).to eq(["risk_assessed"])
    expect(risk.adapter_config).to include("input_artifact_kind" => "dependency_map", "secondary_input_artifact_kind" => "secret_inventory", "output_artifact_kind" => "risk_assessment", "read_only" => true)
    expect(risk.adapter_config.fetch("spawn_targets")).to include("exposed_history" => "security_scan", "missing_secrets_manager" => "incident_readiness")
    expect(risk.agent_prompt).to include("# Credential Risk", "critical")

    plan = queue.stage_configs.find_by!(stage_name: "draft_rotation_plan")
    expect(plan.completion_criteria).to eq(["rotation_planned"])
    expect(plan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
    expect(plan.adapter_config).to include("input_artifact_kind" => "risk_assessment", "secondary_input_artifact_kind" => "dependency_map", "output_artifact_kind" => "rotation_plan", "read_only" => true)
    expect(plan.adapter_config.fetch("spawn_targets")).to include("hardcoded_code_change" => "development", "exposed_history" => "security_scan", "missing_secrets_manager" => "incident_readiness")
    expect(plan.agent_prompt).to include("# Credential Rotation Plan", "Do not rotate")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(["report_present"])
    expect(human_review.timeout_seconds).to eq(86_400)
    expect(human_review.agent_prompt).to include("Do not rotate automatically")

    serialized_queue = Rails.root.join("config/queues/credential_rotation.yml").read
    expect(serialized_queue).to include("file://prompts/credential_scan.md")
    expect(serialized_queue).to include("file://prompts/credential_dependencies.md")
    expect(serialized_queue).to include("file://prompts/credential_risk.md")
    expect(serialized_queue).to include("file://prompts/credential_rotation_plan.md")
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
    expect(serialized_queue).not_to include("working_directory")
  end


  it "seeds the migration safety cookbook queue with resolved portable prompts" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "migration_safety")
    expect(queue.name).to eq("Migration Safety Check")
    expect(queue.stages).to eq(%w[scan_impact enumerate_risks draft_rollback test_rollback draft_runbook human_review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 2,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_impact")
    expect(scan.adapter_type).to eq("inline_claude")
    expect(scan.model_override).to eq("claude-sonnet-4-20250514")
    expect(scan.allowed_skills).to eq(["read_repo"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
    expect(scan.completion_criteria).to eq(["impact_mapped"])
    expect(scan.agent_prompt).to include("# Migration Safety Scan Impact")
    expect(scan.agent_prompt).to include("affected_files")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.agent_prompt).not_to include(Rails.root.to_s)
    expect(scan.adapter_config).to include(
      "output_artifact_kind" => "impact_map",
      "fixture_app" => "cookbooks/fixtures/apps/migration_safety_app"
    )

    enumerate = queue.stage_configs.find_by!(stage_name: "enumerate_risks")
    expect(enumerate.completion_criteria).to eq(["risks_enumerated"])
    expect(enumerate.agent_prompt).to include("blocking")
    expect(enumerate.adapter_config).to include(
      "input_artifact_kind" => "impact_map",
      "output_artifact_kind" => "risk_assessment"
    )

    rollback = queue.stage_configs.find_by!(stage_name: "draft_rollback")
    expect(rollback.completion_criteria).to eq(["rollback_drafted"])
    expect(rollback.agent_prompt).to include("rollback_plan")
    expect(rollback.adapter_config).to include(
      "input_artifact_kind" => "risk_assessment",
      "output_artifact_kind" => "rollback_plan"
    )

    test_rollback = queue.stage_configs.find_by!(stage_name: "test_rollback")
    expect(test_rollback.adapter_type).to eq("docker_compose")
    expect(test_rollback.allowed_skills).to eq(["execute_staging"])
    expect(test_rollback.forbidden_skills).to include("deploy")
    expect(test_rollback.timeout_seconds).to eq(1200)
    expect(test_rollback.completion_criteria).to eq(["rollback_tested"])
    expect(test_rollback.agent_prompt).to include("rollback_test_results")
    expect(test_rollback.adapter_config).to include(
      "input_artifact_kind" => "rollback_plan",
      "output_artifact_kind" => "rollback_test_results",
      "fixture_app" => "cookbooks/fixtures/apps/migration_safety_app",
      "compose_file" => "cookbooks/docker-compose.yml"
    )
    expect(test_rollback.adapter_config).not_to have_key("working_directory")

    runbook = queue.stage_configs.find_by!(stage_name: "draft_runbook")
    expect(runbook.adapter_type).to eq("inline_claude")
    expect(runbook.model_override).to eq("claude-opus-4-20250514")
    expect(runbook.completion_criteria).to eq(["report_present"])
    expect(runbook.agent_prompt).to include("# Migration Safety Draft Runbook")
    expect(runbook.adapter_config).to include(
      "input_artifact_kind" => "rollback_test_results",
      "output_artifact_kind" => "migration_runbook"
    )

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.completion_criteria).to eq(["report_present"])
    expect(human_review.timeout_seconds).to eq(86_400)

    serialized_queue = Rails.root.join("config/queues/migration_safety.yml").read
    expect(serialized_queue).to include("file://cookbooks/prompts/migration_safety/scan_impact.md")
    expect(serialized_queue).to include("cookbooks/docker-compose.yml")
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
  end

  it "is idempotent" do
    2.times { load Rails.root.join("db/seeds.rb") }

    queue = WorkQueue.find_by!(slug: "development")
    shell_queue = WorkQueue.find_by!(slug: "development-shell")
    claude_queue = WorkQueue.find_by!(slug: "development-claude")
    codex_queue = WorkQueue.find_by!(slug: "development-codex")
    expect(WorkQueue.where(slug: "development").count).to eq(1)
    expect(WorkQueue.where(slug: "development-shell").count).to eq(1)
    expect(WorkQueue.where(slug: "development-claude").count).to eq(1)
    expect(WorkQueue.where(slug: "development-codex").count).to eq(1)
    expect(queue.stage_configs.count).to eq(6)
    expect(shell_queue.stage_configs.count).to eq(6)
    expect(claude_queue.stage_configs.count).to eq(6)
    expect(codex_queue.stage_configs.count).to eq(6)
  end
end

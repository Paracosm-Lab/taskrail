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

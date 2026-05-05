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

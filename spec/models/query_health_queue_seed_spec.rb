require "rails_helper"

RSpec.describe "query health queue seed" do
  it "seeds the query health queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "query_health")
    expect(queue.name).to eq("Database Query Health Check")
    expect(queue.stages).to eq(%w[
      collect_queries
      analyze_performance
      draft_fixes
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 2
    )

    collect = queue.stage_configs.find_by!(stage_name: "collect_queries")
    expect(collect.adapter_type).to eq("shell_script")
    expect(collect.model_override).to eq("claude-haiku-4-5-20251001")
    expect(collect.allowed_skills).to include("run_tests", "read_repo")
    expect(collect.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
    expect(collect.completion_criteria).to eq(["query_inventory_produced"])
    expect(collect.agent_prompt).to include("# Query Health Collect Queries")
    expect(collect.agent_prompt).not_to start_with("file://")
    expect(collect.adapter_config).to include(
      "output_artifact_kind" => "query_inventory",
      "fixture_app" => "test/fixtures/apps/slow_queries",
      "docker_profile" => "cookbook-query-health"
    )
    expect(collect.adapter_config["commands"].first["artifact"]).to eq("query_inventory")

    analyze = queue.stage_configs.find_by!(stage_name: "analyze_performance")
    expect(analyze.adapter_type).to eq("inline_claude")
    expect(analyze.model_override).to eq("claude-sonnet-4-20250514")
    expect(analyze.completion_criteria).to eq(["query_analyzed"])
    expect(analyze.agent_prompt).to include("# Query Health Analyze Performance")
    expect(analyze.adapter_config).to include(
      "input_artifact_kind" => "query_inventory",
      "output_artifact_kind" => "query_analysis",
      "spawn_target_queue" => "development"
    )

    draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
    expect(draft.adapter_type).to eq("inline_claude")
    expect(draft.completion_criteria).to eq(["query_fixes_drafted"])
    expect(draft.agent_prompt).to include("# Query Health Draft Fixes")
    expect(draft.adapter_config).to include(
      "input_artifact_kind" => "query_analysis",
      "output_artifact_kind" => "query_patches"
    )

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).to include(
      "input_artifact_kind" => "query_patches",
      "output_artifact_kind" => "test_results",
      "docker_profile" => "cookbook-query-health"
    )

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.agent_prompt).to include("DBA")

    serialized_queue = Rails.root.join("config/queues/query_health.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
  end
end

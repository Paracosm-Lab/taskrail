require "rails_helper"

RSpec.describe "integration test generator cookbook", type: :request do
  def create_fake_integration_queue
    queue = WorkQueue.create!(
      name: "Integration Test Generator Fixture #{SecureRandom.hex(4)}",
      slug: "integration-tests-fixture-#{SecureRandom.hex(4)}",
      stages: %w[map_user_flows identify_boundaries generate_tests run_tests done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )

    queue.stage_configs.create!(stage_name: "map_user_flows", adapter_type: "fake", completion_criteria: ["flows_mapped"])
    queue.stage_configs.create!(stage_name: "identify_boundaries", adapter_type: "fake", completion_criteria: ["boundaries_identified"])
    queue.stage_configs.create!(stage_name: "generate_tests", adapter_type: "fake", completion_criteria: ["tests_generated"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "provides the configured integration_tests queue with docker-friendly shell validation" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "integration_tests")
    expect(queue.stages).to eq(%w[map_user_flows identify_boundaries generate_tests run_tests human_review done])

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands")).to include(
      include(
        "name" => "integration tests cookbook e2e",
        "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb",
        "artifact" => "test_results"
      )
    )
  end

  it "resolves every inline Claude prompt from repo-relative file paths" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "integration_tests")
    %w[map_user_flows identify_boundaries generate_tests].each do |stage_name|
      stage = queue.stage_configs.find_by!(stage_name: stage_name)
      expect(stage.agent_prompt).to be_present
      expect(stage.agent_prompt).not_to start_with("file://")
      expect(stage.agent_prompt).to include("# Integration Tests:")
      expect(stage.agent_prompt).not_to include(Rails.root.to_s)
    end
  end

  it "drives a work item through API creation, engine ticks, adapter runs, artifacts, predicates, and transitions" do
    queue = create_fake_integration_queue

    post "/api/v1/work_items", params: {
      queue: queue.slug,
      title: "Generate integration specs for TaskRail itself",
      spec_url: "docs/specs/cookbook-16-integration-test-generator.md",
      tags: { cookbook: "integration_tests" }
    }

    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending
    expect(work_item.stage_name).to eq("map_user_flows")

    10.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.claims.count).to eq(4)
    expect(work_item.transition_logs.pluck(:from_stage, :to_stage, :trigger)).to include(
      ["map_user_flows", "identify_boundaries", "rule_satisfied"],
      ["identify_boundaries", "generate_tests", "rule_satisfied"],
      ["generate_tests", "run_tests", "rule_satisfied"],
      ["run_tests", "done", "rule_satisfied"]
    )

    expect(work_item.artifacts.pluck(:kind)).to include("user_flows", "boundary_map", "integration_specs", "test_results")
    expect(work_item.artifacts.find_by!(kind: "user_flows").data.fetch("flows").first.fetch("steps")).not_to be_empty
    expect(work_item.artifacts.find_by!(kind: "boundary_map").data.fetch("flows").first.fetch("boundaries")).not_to be_empty
    expect(work_item.artifacts.find_by!(kind: "integration_specs").data.fetch("specs").first).to include(
      "path" => "spec/e2e/create_work_item_flow_spec.rb",
      "flow_name" => "Create work item and advance"
    )
    expect(work_item.artifacts.find_by!(kind: "test_results").data).to include("passed" => true)
  end

  it "keeps queue YAML portable and references only repo-relative prompt files" do
    yaml = Rails.root.join("config/queues/integration_tests.yml").read

    expect(yaml).not_to include(Rails.root.to_s)
    expect(yaml).not_to include("/Users/")
    expect(yaml).not_to include("file:///")
    expect(yaml).not_to include("working_directory:")
    expect(yaml.scan(/file:\/\/prompts\/integration_[a-z_]+\.md/).uniq).to contain_exactly(
      "file://prompts/integration_map_flows.md",
      "file://prompts/integration_boundaries.md",
      "file://prompts/integration_generate.md"
    )
  end

  it "covers the source cookbook spec stages, artifacts, and predicates" do
    source_spec = Rails.root.join("docs/specs/cookbook-16-integration-test-generator.md").read
    queue_yaml = Rails.root.join("config/queues/integration_tests.yml").read

    %w[
      map_user_flows
      identify_boundaries
      generate_tests
      run_tests
      human_review
      done
      user_flows
      boundary_map
      integration_specs
      flows_mapped
      boundaries_identified
      tests_generated
      tests_passed
    ].each do |required_term|
      expect(source_spec).to include(required_term)
      expect(queue_yaml).to include(required_term)
    end
  end
end

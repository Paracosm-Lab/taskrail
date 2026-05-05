module Adapters
  class FakeAdapter < BaseAdapter
    def execute(assignment)
      stage_name = assignment.fetch(:stage).fetch(:name)

      case stage_name
      when "intake"
        intake_result(assignment)
      when "decompose"
        decompose_result(assignment)
      when "build"
        build_result(assignment)
      when "test"
        test_result(assignment)
      when "review"
        review_result(assignment)
      when "map_user_flows"
        map_user_flows_result
      when "identify_boundaries"
        identify_boundaries_result
      when "generate_tests"
        generate_integration_tests_result
      when "run_tests"
        integration_run_tests_result
      else
        generic_result(stage_name)
      end
    end

    private

    def intake_result(_assignment)
      AgentResult.success(
        report: {
          "summary" => "classified work item",
          "tags" => { "risk" => "low", "complexity" => "small", "cost" => "low" }
        },
        trace_events: [trace_event("classified work item")]
      )
    end

    def decompose_result(assignment)
      title = assignment.fetch(:work_item).fetch(:title)
      spec_url = assignment.fetch(:work_item)[:spec_url]

      AgentResult.success(
        report: {
          "summary" => "decomposed work item",
          "children" => [
            {
              "title" => "Build #{title}",
              "spec_url" => spec_url,
              "tags" => { "complexity" => "small" }
            }
          ]
        },
        trace_events: [trace_event("created child work item definitions")]
      )
    end

    def build_result(assignment)
      id = assignment.fetch(:work_item)[:id] || "unknown"

      AgentResult.success(
        report: { "summary" => "created implementation branch" },
        artifacts: [
          { "kind" => "branch", "data" => { "name" => "sc/#{id}" } }
        ],
        trace_events: [trace_event("created fake branch artifact")]
      )
    end

    def test_result(_assignment)
      AgentResult.success(
        report: { "summary" => "validated branch" },
        artifacts: [
          { "kind" => "test_results", "data" => { "passed" => true } },
          { "kind" => "lint", "data" => { "clean" => true } },
          { "kind" => "coverage", "data" => { "current" => 95.0, "previous" => 94.0 } }
        ],
        trace_events: [trace_event("validated fake branch")]
      )
    end

    def review_result(_assignment)
      AgentResult.success(
        report: { "summary" => "approved fake diff", "verdict" => "approved" },
        trace_events: [trace_event("approved fake diff")]
      )
    end

    def generic_result(stage_name)
      AgentResult.success(
        report: { "summary" => "completed #{stage_name}" },
        trace_events: [trace_event("completed #{stage_name}")]
      )
    end

    def map_user_flows_result
      AgentResult.success(
        report: { "summary" => "mapped StupidClaw self-integration flow" },
        artifacts: [
          {
            "kind" => "user_flows",
            "data" => {
              "flows" => [
                {
                  "name" => "Create work item and advance",
                  "entry_point" => "POST /api/v1/work_items",
                  "steps" => [
                    { "action" => "create work item", "service" => "Api::V1::WorkItemsController", "endpoint_or_method" => "create", "data_deps" => ["integration queue"] },
                    { "action" => "run engine tick", "service" => "Engine::Runner", "endpoint_or_method" => "call", "data_deps" => ["pending work item"] }
                  ],
                  "expected_outcome" => "work item advances after predicates pass",
                  "services_involved" => ["API", "Engine::Runner", "Adapters::FakeAdapter", "Engine::TransitionManager", "Database"]
                }
              ]
            }
          }
        ],
        trace_events: [trace_event("mapped integration user flows")]
      )
    end

    def identify_boundaries_result
      AgentResult.success(
        report: { "summary" => "identified StupidClaw self-integration boundaries" },
        artifacts: [
          {
            "kind" => "boundary_map",
            "data" => {
              "flows" => [
                {
                  "name" => "Create work item and advance",
                  "boundaries" => [
                    { "from" => "HTTP client", "to" => "Api::V1::WorkItemsController", "contract" => "creates pending work item", "stub_strategy" => "real request" },
                    { "from" => "Engine::Runner", "to" => "Adapters::FakeAdapter", "contract" => "claim result includes reports/artifacts", "stub_strategy" => "fake adapter" },
                    { "from" => "Engine::TransitionManager", "to" => "Engine::PredicateRegistry", "contract" => "artifacts satisfy criteria", "stub_strategy" => "real predicates" }
                  ],
                  "setup_data" => ["seeded queue", "pending work item"],
                  "teardown" => "database cleanup"
                }
              ]
            }
          }
        ],
        trace_events: [trace_event("identified integration boundaries")]
      )
    end

    def generate_integration_tests_result
      AgentResult.success(
        report: { "summary" => "generated integration specs" },
        artifacts: [
          {
            "kind" => "integration_specs",
            "data" => {
              "specs" => [
                {
                  "path" => "spec/e2e/create_work_item_flow_spec.rb",
                  "content" => "require \"rails_helper\"\n\nRSpec.describe \"create work item flow\" do\n  it \"advances\" do\n    expect(true).to be(true)\n  end\nend\n",
                  "flow_name" => "Create work item and advance",
                  "boundaries_tested" => ["API", "Engine", "Adapter", "Database"]
                }
              ]
            }
          }
        ],
        trace_events: [trace_event("generated integration specs")]
      )
    end

    def integration_run_tests_result
      AgentResult.success(
        report: { "summary" => "integration specs passed" },
        artifacts: [
          { "kind" => "test_results", "data" => { "passed" => true, "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb" } }
        ],
        trace_events: [trace_event("ran integration specs")]
      )
    end

    def trace_event(summary)
      {
        "event_type" => "decision",
        "output_summary" => summary,
        "duration_ms" => 1,
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0
      }
    end
  end
end

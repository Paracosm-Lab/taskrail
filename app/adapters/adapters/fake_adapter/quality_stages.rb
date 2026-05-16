module Adapters
  class FakeAdapter
    module QualityStages
      def coverage_check_result(_assignment)
        AgentResult.success(
          report: { "summary" => "checked PR coverage" },
          artifacts: [
            {
              "kind" => "coverage_report",
              "data" => {
                "overall_delta" => 0.0,
                "changed_files" => [],
                "new_files_without_tests" => []
              }
            }
          ],
          trace_events: [trace_event("checked PR coverage")]
        )
      end

      def architectural_review_result(_assignment)
        AgentResult.success(
          report: { "summary" => "approved PR architecture", "verdict" => "approved" },
          trace_events: [trace_event("approved PR architecture")]
        )
      end

      def scan_error_handling_result(_assignment)
        AgentResult.success(
          report: { "summary" => "found error patterns" },
          artifacts: [{ "kind" => "error_patterns", "data" => { "patterns" => [{ "file" => "app/services/payment.rb", "line" => 12, "type" => "bare_rescue", "severity" => "high" }] } }],
          trace_events: [trace_event("found error patterns")]
        )
      end

      def classify_severity_result(_assignment)
        AgentResult.success(
          report: { "summary" => "classified severity" },
          artifacts: [{ "kind" => "severity_report", "data" => { "findings" => [{ "id" => "f1", "severity" => "high", "file" => "app/services/payment.rb" }] } }],
          trace_events: [trace_event("classified severity")]
        )
      end

      def draft_fixes_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted fixes" },
          artifacts: [
            { "kind" => "fix_patches", "data" => { "patches" => [{ "file" => "app/services/payment.rb", "patch" => "rescue specific errors" }] } },
            { "kind" => "query_patches", "data" => { "migrations" => ["add_index_on_users_email"], "code_patches" => [{ "file" => "app/models/user.rb", "patch" => "add index hint" }] } }
          ],
          trace_events: [trace_event("drafted fixes")]
        )
      end

      def scan_log_statements_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned log statements" },
          artifacts: [{ "kind" => "log_inventory", "data" => { "statements" => [{ "file" => "app/controllers/orders_controller.rb", "line" => 3, "logger" => "puts", "level" => "unknown", "format" => "debug_output" }] } }],
          trace_events: [trace_event("scanned log statements")]
        )
      end

      def assess_quality_result(_assignment)
        AgentResult.success(
          report: { "summary" => "assessed quality" },
          artifacts: [{ "kind" => "logging_assessment", "data" => { "best_patterns" => [], "worst_offenders" => [], "scores_by_file" => {}, "recommended_standard" => {} } }],
          trace_events: [trace_event("assessed quality")]
        )
      end

      def draft_standard_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted standard" },
          artifacts: [{ "kind" => "logging_standard", "data" => { "standard" => { "format" => "structured_json" } } }],
          trace_events: [trace_event("drafted standard")]
        )
      end

      def scan_coverage_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned coverage" },
          artifacts: [{ "kind" => "coverage_map", "data" => { "files" => [{ "path" => "app/services/payment.rb", "coverage" => 0.0 }] } }],
          trace_events: [trace_event("scanned coverage")]
        )
      end

      def identify_gaps_result(_assignment)
        AgentResult.success(
          report: { "summary" => "identified gaps" },
          artifacts: [
            { "kind" => "test_plan", "data" => { "units" => [{ "file" => "app/services/payment.rb", "tests" => ["test payment processing"] }] } },
            { "kind" => "gap_analysis", "data" => { "platform_gaps" => [{ "area" => "alerting", "gap" => "no PagerDuty runbook" }] } }
          ],
          trace_events: [trace_event("identified gaps")]
        )
      end

      def map_user_flows_result(_assignment)
        AgentResult.success(
          report: { "summary" => "mapped TaskRail self-integration flow" },
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

      def identify_boundaries_result(_assignment)
        AgentResult.success(
          report: { "summary" => "identified TaskRail self-integration boundaries" },
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
    end
  end
end

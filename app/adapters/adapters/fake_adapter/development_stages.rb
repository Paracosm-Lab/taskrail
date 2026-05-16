module Adapters
  class FakeAdapter
    module DevelopmentStages
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

      def generate_integration_tests_result(_assignment)
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

      def integration_run_tests_result(_assignment)
        AgentResult.success(
          report: { "summary" => "integration specs passed" },
          artifacts: [
            { "kind" => "test_results", "data" => { "passed" => true, "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb" } }
          ],
          trace_events: [trace_event("ran integration specs")]
        )
      end

      def fix_result(assignment)
        id = assignment.dig(:work_item, :id) || SecureRandom.hex(4)
        AgentResult.success(
          report: { "summary" => "applied fix and committed to branch" },
          artifacts: [{ "kind" => "branch", "data" => { "name" => "postrunner/fix-#{id}", "branch" => "postrunner/fix-#{id}" } }],
          trace_events: [trace_event("applied postrunner fix")]
        )
      end

      def open_pr_result(_assignment)
        AgentResult.success(
          report: { "summary" => "opened pull request" },
          artifacts: [{ "kind" => "pull_request", "data" => { "number" => 1, "url" => "https://github.com/fake/repo/pull/1", "branch" => "postrunner/fix-fake", "base_branch" => "main" } }],
          trace_events: [trace_event("opened fake pull request")]
        )
      end

      def await_ci_result(_assignment)
        AgentResult.success(
          report: { "summary" => "CI passed" },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "success", "checks" => [], "pr_number" => 1 } }],
          trace_events: [trace_event("CI checks passed")]
        )
      end

      def merge_result(_assignment)
        AgentResult.success(
          report: { "summary" => "merged pull request" },
          artifacts: [{ "kind" => "merge_result", "data" => { "pr_number" => 1, "strategy" => "squash", "merged" => true } }],
          trace_events: [trace_event("merged fake pull request")]
        )
      end
    end
  end
end

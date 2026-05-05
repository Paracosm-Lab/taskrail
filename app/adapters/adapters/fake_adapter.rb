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

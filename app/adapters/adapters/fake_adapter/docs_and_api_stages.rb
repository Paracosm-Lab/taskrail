module Adapters
  class FakeAdapter
    module DocsAndApiStages
      def scan_endpoints_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned endpoints", "endpoint_inventory" => { "endpoints" => [{ "path" => "/api/v1/work_items", "method" => "GET", "controller" => "Api::V1::WorkItemsController" }] } },
          trace_events: [trace_event("scanned endpoints")]
        )
      end

      def diff_existing_docs_result(_assignment)
        AgentResult.success(
          report: { "summary" => "diffed docs", "docs_diff" => { "missing" => [{ "endpoint" => "/api/v1/work_items", "action" => "add" }], "stale" => [], "incorrect" => [] } },
          trace_events: [trace_event("diffed docs")]
        )
      end

      def draft_documentation_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted documentation", "draft_docs" => { "files" => [{ "path" => "docs/api/work_items.md", "content" => "# Work Items API" }] } },
          trace_events: [trace_event("drafted documentation")]
        )
      end

      def validate_examples_result(_assignment)
        AgentResult.success(
          report: { "summary" => "validated examples", "validation_results" => { "valid" => true, "errors" => [] } },
          trace_events: [trace_event("validated examples")]
        )
      end

      def scan_references_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned references" },
          artifacts: [{ "kind" => "removal_candidates", "data" => { "candidates" => [{ "file" => "app/services/legacy.rb", "reason" => "no references found" }] } }],
          trace_events: [trace_event("scanned references")]
        )
      end

      def verify_unused_result(_assignment)
        AgentResult.success(
          report: { "summary" => "verified unused" },
          artifacts: [{ "kind" => "verified_removals", "data" => { "removals" => [{ "file" => "app/services/legacy.rb", "classification" => "safe_to_remove" }] } }],
          trace_events: [trace_event("verified unused")]
        )
      end

      def draft_removals_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted removals" },
          artifacts: [{ "kind" => "removal_patches", "data" => { "patches" => [{ "file" => "app/services/legacy.rb", "action" => "delete" }] } }],
          trace_events: [trace_event("drafted removals")]
        )
      end
    end
  end
end

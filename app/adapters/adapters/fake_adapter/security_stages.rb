module Adapters
  class FakeAdapter
    module SecurityStages
      def pr_security_scan_result(_assignment)
        AgentResult.success(
          report: { "summary" => "reviewed PR security impact" },
          artifacts: [
            { "kind" => "security_findings", "data" => { "findings" => [], "blocking_count" => 0 } }
          ],
          trace_events: [trace_event("reviewed PR security impact")]
        )
      end

      def scan_vulnerabilities_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned vulnerabilities" },
          artifacts: [{ "kind" => "vulnerability_scan", "data" => { "vulnerabilities" => [{ "id" => "CVE-2024-0001", "severity" => "high", "package" => "rack" }] } }],
          trace_events: [trace_event("scanned vulnerabilities")]
        )
      end

      def define_rules_result(_assignment)
        AgentResult.success(
          report: { "summary" => "defined rules" },
          artifacts: [{ "kind" => "integrity_rules", "data" => { "rules" => [{ "name" => "no_orphan_work_items", "description" => "every work item belongs to a valid queue" }] } }],
          trace_events: [trace_event("defined rules")]
        )
      end

      def scan_violations_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned violations" },
          artifacts: [{ "kind" => "violation_report", "data" => { "results" => [{ "rule" => "no_orphan_work_items", "violations" => 0 }] } }],
          trace_events: [trace_event("scanned violations")]
        )
      end

      def scan_secrets_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned secrets" },
          artifacts: [{ "kind" => "secret_inventory", "data" => { "secrets" => [{ "name" => "DATABASE_URL", "location" => ".env", "last_rotated" => "2024-01-01" }] } }],
          trace_events: [trace_event("scanned secrets")]
        )
      end

      def map_dependencies_result(_assignment)
        AgentResult.success(
          report: { "summary" => "mapped dependencies" },
          artifacts: [{ "kind" => "dependency_map", "data" => { "credentials" => [{ "name" => "DATABASE_URL", "consumers" => ["app/config/database.yml"] }] } }],
          trace_events: [trace_event("mapped dependencies")]
        )
      end

      def assess_risk_result(_assignment)
        AgentResult.success(
          report: { "summary" => "assessed risk" },
          artifacts: [{ "kind" => "risk_assessment", "data" => { "credentials" => [{ "name" => "DATABASE_URL", "risk" => "high" }], "summary" => { "high_risk_count" => 1 } } }],
          trace_events: [trace_event("assessed risk")]
        )
      end

      def draft_rotation_plan_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted rotation plan" },
          artifacts: [{ "kind" => "rotation_plan", "data" => { "rotations" => [{ "credential" => "DATABASE_URL", "steps" => ["generate new password", "update vault", "restart app"] }] } }],
          trace_events: [trace_event("drafted rotation plan")]
        )
      end
    end
  end
end

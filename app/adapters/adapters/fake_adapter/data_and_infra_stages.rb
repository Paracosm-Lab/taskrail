module Adapters
  class FakeAdapter
    module DataAndInfraStages
      def collect_queries_result(_assignment)
        AgentResult.success(
          report: { "summary" => "collected queries" },
          artifacts: [{ "kind" => "query_inventory", "data" => { "queries" => [{ "model" => "User", "query" => "User.all", "location" => "app/controllers/users_controller.rb:10" }] } }],
          trace_events: [trace_event("collected queries")]
        )
      end

      def analyze_performance_result(_assignment)
        AgentResult.success(
          report: { "summary" => "analyzed performance" },
          artifacts: [{ "kind" => "query_analysis", "data" => { "findings" => [{ "query" => "User.all", "issue" => "full table scan", "severity" => "high" }] } }],
          trace_events: [trace_event("analyzed performance")]
        )
      end

      def audit_dependencies_result(_assignment)
        AgentResult.success(
          report: { "summary" => "audited dependencies" },
          artifacts: [{ "kind" => "dependency_audit", "data" => { "dependencies" => [{ "name" => "rack", "current" => "2.2.8", "latest" => "3.0.9", "outdated" => true }] } }],
          trace_events: [trace_event("audited dependencies")]
        )
      end

      def prioritize_upgrades_result(_assignment)
        AgentResult.success(
          report: { "summary" => "prioritized upgrades" },
          artifacts: [{ "kind" => "upgrade_plan", "data" => { "upgrades" => [{ "deps" => ["rack"], "priority" => 1, "risk" => "medium", "reason" => "CVE fix" }] } }],
          trace_events: [trace_event("prioritized upgrades")]
        )
      end

      def upgrade_one_result(_assignment)
        AgentResult.success(
          report: { "summary" => "upgraded one dependency" },
          artifacts: [{ "kind" => "upgrade_patches", "data" => { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "3.0.9", "patches" => [{ "file" => "Gemfile", "original" => "rack 2.2.8", "replacement" => "rack 3.0.9" }] } }],
          trace_events: [trace_event("upgraded one dependency")]
        )
      end

      def scan_impact_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned impact" },
          artifacts: [{ "kind" => "impact_map", "data" => { "affected_files" => ["app/models/user.rb", "spec/models/user_spec.rb"] } }],
          trace_events: [trace_event("scanned impact")]
        )
      end

      def enumerate_risks_result(_assignment)
        AgentResult.success(
          report: { "summary" => "enumerated risks" },
          artifacts: [{ "kind" => "risk_assessment", "data" => { "risks" => [{ "description" => "table lock during migration", "severity" => "high" }] } }],
          trace_events: [trace_event("enumerated risks")]
        )
      end

      def draft_rollback_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted rollback" },
          artifacts: [{ "kind" => "rollback_plan", "data" => { "procedures" => [{ "name" => "rollback migration", "steps" => [{ "action" => "run rollback migration", "command" => "rails db:rollback" }] }] } }],
          trace_events: [trace_event("drafted rollback")]
        )
      end

      def test_rollback_result(_assignment)
        AgentResult.success(
          report: { "summary" => "tested rollback" },
          artifacts: [{ "kind" => "rollback_test_results", "data" => { "migration_succeeded" => true, "rollback_succeeded" => true, "data_intact" => true, "health_checks_passed" => true } }],
          trace_events: [trace_event("tested rollback")]
        )
      end

      def assess_damage_result(_assignment)
        AgentResult.success(
          report: { "summary" => "assessed damage" },
          artifacts: [{ "kind" => "damage_assessment", "data" => { "findings" => [{ "table" => "work_items", "severity" => "low", "description" => "minor inconsistency" }] } }],
          trace_events: [trace_event("assessed damage")]
        )
      end

      def draft_repairs_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted repairs" },
          artifacts: [{ "kind" => "repair_scripts", "data" => { "repairs" => [{ "name" => "fix_orphans", "sql" => "DELETE FROM work_items WHERE work_queue_id IS NULL" }] } }],
          trace_events: [trace_event("drafted repairs")]
        )
      end

      def ingest_artifacts_result(_assignment)
        AgentResult.success(
          report: { "summary" => "ingested artifacts" },
          artifacts: [{ "kind" => "incident_artifacts", "data" => { "sentry_events" => [{ "id" => "abc123", "title" => "NoMethodError in PaymentService" }], "slack_messages" => [], "deploys" => [] } }],
          trace_events: [trace_event("ingested artifacts")]
        )
      end

      def reconstruct_timeline_result(_assignment)
        AgentResult.success(
          report: { "summary" => "reconstructed timeline" },
          artifacts: [{ "kind" => "incident_timeline", "data" => { "phases" => [{ "name" => "detection", "start" => "2024-01-01T00:00:00Z", "end" => "2024-01-01T00:05:00Z" }], "total_duration_minutes" => 45 } }],
          trace_events: [trace_event("reconstructed timeline")]
        )
      end

      def analyze_root_cause_result(_assignment)
        AgentResult.success(
          report: { "summary" => "analyzed root cause" },
          artifacts: [{ "kind" => "root_cause_analysis", "data" => { "root_cause" => "Memory leak in payment processor under high load", "contributing_factors" => ["no memory limit set"] } }],
          trace_events: [trace_event("analyzed root cause")]
        )
      end

      def evaluate_response_result(_assignment)
        AgentResult.success(
          report: { "summary" => "evaluated response" },
          artifacts: [{ "kind" => "response_evaluation", "data" => { "grade" => "B", "strengths" => ["fast detection"], "weaknesses" => ["slow remediation"] } }],
          trace_events: [trace_event("evaluated response")]
        )
      end

      def draft_updates_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted updates" },
          artifacts: [{ "kind" => "incident_updates", "data" => { "runbook_updates" => [{ "runbook" => "database-recovery", "update" => "Add connection pool check step" }], "new_alerts" => [] } }],
          trace_events: [trace_event("drafted updates")]
        )
      end

      def collect_configs_result(_assignment)
        AgentResult.success(
          report: { "summary" => "collected configs" },
          artifacts: [{ "kind" => "environment_configs", "data" => { "environments" => { "production" => { "database_pool" => 5, "log_level" => "warn" }, "staging" => { "database_pool" => 2, "log_level" => "debug" } } } }],
          trace_events: [trace_event("collected configs")]
        )
      end

      def diff_environments_result(_assignment)
        AgentResult.success(
          report: { "summary" => "diffed environments" },
          artifacts: [{ "kind" => "environment_diff", "data" => { "comparisons" => [{ "key" => "database_pool", "production" => 5, "staging" => 2, "drift" => true }] } }],
          trace_events: [trace_event("diffed environments")]
        )
      end

      def classify_drift_result(_assignment)
        AgentResult.success(
          report: { "summary" => "classified drift" },
          artifacts: [{ "kind" => "drift_classification", "data" => { "drifts" => [{ "key" => "database_pool", "severity" => "medium", "action" => "sync_staging" }] } }],
          trace_events: [trace_event("classified drift")]
        )
      end

      def draft_sync_plan_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted sync plan" },
          artifacts: [{ "kind" => "sync_plan", "data" => { "actions" => [{ "environment" => "staging", "key" => "database_pool", "from" => 2, "to" => 5, "command" => "set DATABASE_POOL=5" }] } }],
          trace_events: [trace_event("drafted sync plan")]
        )
      end
    end
  end
end

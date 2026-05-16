module Adapters
  class FakeAdapter
    module OperationalStages
      def cluster_failures_result(_assignment)
        AgentResult.success(
          report: { "summary" => "clustered operational failures" },
          artifacts: [
            { "kind" => "clusters", "data" => { "clusters" => [{ "name" => "db-pool", "signals" => 3 }] } }
          ],
          trace_events: [trace_event("clustered operational failures")]
        )
      end

      def assess_instrumentation_result(_assignment)
        AgentResult.success(
          report: { "summary" => "assessed operational instrumentation" },
          artifacts: [
            { "kind" => "instrumentation_assessment", "data" => { "complete" => true, "gaps" => [] } }
          ],
          trace_events: [trace_event("assessed operational instrumentation")]
        )
      end

      def map_runbooks_result(_assignment)
        AgentResult.success(
          report: { "summary" => "mapped operational runbooks" },
          artifacts: [
            { "kind" => "runbook_mapping", "data" => { "mappings" => [{ "cluster" => "db-pool", "runbook" => "database_pool_saturation" }] } }
          ],
          trace_events: [trace_event("mapped operational runbooks")]
        )
      end

      def draft_runbook_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted operational runbook" },
          artifacts: [
            { "kind" => "runbook_draft", "data" => { "title" => "Database pool saturation", "steps" => ["inspect pool", "scale workers"] } }
          ],
          trace_events: [trace_event("drafted operational runbook")]
        )
      end

      def staging_validation_result(_assignment)
        AgentResult.success(
          report: { "summary" => "validated runbook in staging", "validation_passed" => true },
          trace_events: [trace_event("validated runbook in staging")]
        )
      end

      def run_checks_result(_assignment)
        AgentResult.success(
          report: { "summary" => "PR checks passed" },
          artifacts: [
            {
              "kind" => "check_results",
              "data" => {
                "lint" => { "passed" => true, "errors" => [] },
                "tests" => { "passed" => true, "failures" => [] },
                "build" => { "passed" => true, "errors" => [] }
              }
            }
          ],
          trace_events: [trace_event("ran PR checks")]
        )
      end

      def detect_alerts_result(_assignment)
        AgentResult.success(
          report: { "summary" => "detected alerts" },
          artifacts: [{ "kind" => "detected_alerts", "data" => { "events" => [{ "source" => "PagerDuty", "title" => "High error rate", "severity" => "critical" }] } }],
          trace_events: [trace_event("detected alerts")]
        )
      end

      def diagnose_failure_result(_assignment)
        AgentResult.success(
          report: { "summary" => "diagnosed failure" },
          artifacts: [{ "kind" => "diagnosis", "data" => { "root_cause_hypothesis" => "Database connection pool exhausted", "confidence" => "high" } }],
          trace_events: [trace_event("diagnosed failure")]
        )
      end

      def select_runbook_result(_assignment)
        AgentResult.success(
          report: { "summary" => "selected runbook" },
          artifacts: [{ "kind" => "runbook_selection", "data" => { "runbook" => "database-recovery", "reason" => "matches diagnosis" } }],
          trace_events: [trace_event("selected runbook")]
        )
      end

      def execute_runbook_result(_assignment)
        AgentResult.success(
          report: { "summary" => "executed runbook" },
          artifacts: [{ "kind" => "runbook_execution", "data" => { "steps_executed" => ["restart connection pool", "verify health"], "outcome" => "success" } }],
          trace_events: [trace_event("executed runbook")]
        )
      end

      def verify_recovery_result(_assignment)
        AgentResult.success(
          report: { "summary" => "verified recovery" },
          artifacts: [{ "kind" => "recovery_verification", "data" => { "service_healthy" => true, "checks" => { "api" => "passing", "database" => "passing" } } }],
          trace_events: [trace_event("verified recovery")]
        )
      end

      def scan_job_classes_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scanned job classes" },
          artifacts: [{ "kind" => "job_inventory", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "queue" => "default" }] } }],
          trace_events: [trace_event("scanned job classes")]
        )
      end

      def assess_observability_result(_assignment)
        AgentResult.success(
          report: { "summary" => "assessed observability" },
          artifacts: [
            { "kind" => "job_inventory", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "queue" => "default" }] } },
            { "kind" => "observability_assessment", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "has_logging" => false, "has_metrics" => false }] } }
          ],
          trace_events: [trace_event("assessed observability")]
        )
      end

      def inventory_services_result(_assignment)
        AgentResult.success(
          report: { "summary" => "inventoried services" },
          artifacts: [{ "kind" => "service_inventory", "data" => { "services" => [{ "name" => "api", "tier" => 1 }] } }],
          trace_events: [trace_event("inventoried services")]
        )
      end

      def score_readiness_result(_assignment)
        AgentResult.success(
          report: { "summary" => "scored readiness" },
          artifacts: [
            { "kind" => "service_inventory", "data" => { "services" => [{ "name" => "api", "tier" => 1 }] } },
            { "kind" => "readiness_scores", "data" => { "services" => [{ "name" => "api", "scores" => { "runbook" => 7 }, "total_score" => 7, "grade" => "C" }] } }
          ],
          trace_events: [trace_event("scored readiness")]
        )
      end

      def draft_improvements_result(_assignment)
        AgentResult.success(
          report: { "summary" => "drafted improvements" },
          artifacts: [{ "kind" => "improvement_drafts", "data" => { "improvements" => [{ "service" => "api", "files" => [{ "path" => "docs/runbooks/api.md", "content" => "# API Runbook" }] }] } }],
          trace_events: [trace_event("drafted improvements")]
        )
      end

      def plan_disruption_result(_assignment)
        AgentResult.success(
          report: { "summary" => "planned disruption" },
          artifacts: [{ "kind" => "disruption_plan", "data" => { "scenario" => "kill database connection", "reversal_steps" => ["restart connection pool"] } }],
          trace_events: [trace_event("planned disruption")]
        )
      end

      def execute_disruption_result(_assignment)
        AgentResult.success(
          report: { "summary" => "executed disruption" },
          artifacts: [{ "kind" => "disruption_record", "data" => { "commands_run" => ["kill -9 postgres"] } }],
          trace_events: [trace_event("executed disruption")]
        )
      end

      def monitor_impact_result(_assignment)
        AgentResult.success(
          report: { "summary" => "monitored impact" },
          artifacts: [{ "kind" => "impact_report", "data" => { "affected_services" => ["api"], "error_rate_spike" => true } }],
          trace_events: [trace_event("monitored impact")]
        )
      end

      def evaluate_recovery_result(_assignment)
        AgentResult.success(
          report: { "summary" => "evaluated recovery" },
          artifacts: [{ "kind" => "recovery_evaluation", "data" => { "scores" => { "detection" => 8, "response" => 7, "recovery" => 9 } } }],
          trace_events: [trace_event("evaluated recovery")]
        )
      end
    end
  end
end

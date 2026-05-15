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
      when "scan_error_handling" then scan_error_handling_result
      when "classify_severity" then classify_severity_result
      when "draft_fixes" then draft_fixes_result
      when "scan_endpoints" then scan_endpoints_result
      when "diff_existing_docs" then diff_existing_docs_result
      when "draft_documentation" then draft_documentation_result
      when "validate_examples" then validate_examples_result
      when "scan_references" then scan_references_result
      when "verify_unused" then verify_unused_result
      when "draft_removals" then draft_removals_result
      when "collect_queries" then collect_queries_result
      when "analyze_performance" then analyze_performance_result
      when "scan_coverage" then scan_coverage_result
      when "identify_gaps" then identify_gaps_result
      when "scan_log_statements" then scan_log_statements_result
      when "assess_quality" then assess_quality_result
      when "draft_standard" then draft_standard_result
      when "plan_disruption" then plan_disruption_result
      when "execute_disruption" then execute_disruption_result
      when "monitor_impact" then monitor_impact_result
      when "evaluate_recovery" then evaluate_recovery_result
      when "detect_alerts" then detect_alerts_result
      when "diagnose_failure" then diagnose_failure_result
      when "select_runbook" then select_runbook_result
      when "execute_runbook" then execute_runbook_result
      when "verify_recovery" then verify_recovery_result
      when "scan_job_classes" then scan_job_classes_result
      when "assess_observability" then assess_observability_result
      when "inventory_services" then inventory_services_result
      when "score_readiness" then score_readiness_result
      when "draft_improvements" then draft_improvements_result
      when "scan_secrets" then scan_secrets_result
      when "map_dependencies" then map_dependencies_result
      when "assess_risk" then assess_risk_result
      when "draft_rotation_plan" then draft_rotation_plan_result
      when "audit_dependencies" then audit_dependencies_result
      when "prioritize_upgrades" then prioritize_upgrades_result
      when "upgrade_one" then upgrade_one_result
      when "scan_impact" then scan_impact_result
      when "enumerate_risks" then enumerate_risks_result
      when "draft_rollback" then draft_rollback_result
      when "test_rollback" then test_rollback_result
      when "scan_vulnerabilities" then scan_vulnerabilities_result
      when "define_rules" then define_rules_result
      when "scan_violations" then scan_violations_result
      when "assess_damage" then assess_damage_result
      when "draft_repairs" then draft_repairs_result
      when "ingest_artifacts" then ingest_artifacts_result
      when "reconstruct_timeline" then reconstruct_timeline_result
      when "analyze_root_cause" then analyze_root_cause_result
      when "evaluate_response" then evaluate_response_result
      when "draft_updates" then draft_updates_result
      when "collect_configs" then collect_configs_result
      when "diff_environments" then diff_environments_result
      when "classify_drift" then classify_drift_result
      when "draft_sync_plan" then draft_sync_plan_result
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

    def identify_boundaries_result
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

    def scan_error_handling_result
      AgentResult.success(
        report: { "summary" => "found error patterns" },
        artifacts: [{ "kind" => "error_patterns", "data" => { "patterns" => [{ "file" => "app/services/payment.rb", "line" => 12, "type" => "bare_rescue", "severity" => "high" }] } }],
        trace_events: [trace_event("found error patterns")]
      )
    end

    def classify_severity_result
      AgentResult.success(
        report: { "summary" => "classified severity" },
        artifacts: [{ "kind" => "severity_report", "data" => { "findings" => [{ "id" => "f1", "severity" => "high", "file" => "app/services/payment.rb" }] } }],
        trace_events: [trace_event("classified severity")]
      )
    end

    def draft_fixes_result
      AgentResult.success(
        report: { "summary" => "drafted fixes" },
        artifacts: [
          { "kind" => "fix_patches", "data" => { "patches" => [{ "file" => "app/services/payment.rb", "patch" => "rescue specific errors" }] } },
          { "kind" => "query_patches", "data" => { "migrations" => ["add_index_on_users_email"], "code_patches" => [{ "file" => "app/models/user.rb", "patch" => "add index hint" }] } }
        ],
        trace_events: [trace_event("drafted fixes")]
      )
    end

    def scan_endpoints_result
      AgentResult.success(
        report: { "summary" => "scanned endpoints", "endpoint_inventory" => { "endpoints" => [{ "path" => "/api/v1/work_items", "method" => "GET", "controller" => "Api::V1::WorkItemsController" }] } },
        trace_events: [trace_event("scanned endpoints")]
      )
    end

    def diff_existing_docs_result
      AgentResult.success(
        report: { "summary" => "diffed docs", "docs_diff" => { "missing" => [{ "endpoint" => "/api/v1/work_items", "action" => "add" }], "stale" => [], "incorrect" => [] } },
        trace_events: [trace_event("diffed docs")]
      )
    end

    def draft_documentation_result
      AgentResult.success(
        report: { "summary" => "drafted documentation", "draft_docs" => { "files" => [{ "path" => "docs/api/work_items.md", "content" => "# Work Items API" }] } },
        trace_events: [trace_event("drafted documentation")]
      )
    end

    def validate_examples_result
      AgentResult.success(
        report: { "summary" => "validated examples", "validation_results" => { "valid" => true, "errors" => [] } },
        trace_events: [trace_event("validated examples")]
      )
    end

    def scan_references_result
      AgentResult.success(
        report: { "summary" => "scanned references" },
        artifacts: [{ "kind" => "removal_candidates", "data" => { "candidates" => [{ "file" => "app/services/legacy.rb", "reason" => "no references found" }] } }],
        trace_events: [trace_event("scanned references")]
      )
    end

    def verify_unused_result
      AgentResult.success(
        report: { "summary" => "verified unused" },
        artifacts: [{ "kind" => "verified_removals", "data" => { "removals" => [{ "file" => "app/services/legacy.rb", "classification" => "safe_to_remove" }] } }],
        trace_events: [trace_event("verified unused")]
      )
    end

    def draft_removals_result
      AgentResult.success(
        report: { "summary" => "drafted removals" },
        artifacts: [{ "kind" => "removal_patches", "data" => { "patches" => [{ "file" => "app/services/legacy.rb", "action" => "delete" }] } }],
        trace_events: [trace_event("drafted removals")]
      )
    end

    def collect_queries_result
      AgentResult.success(
        report: { "summary" => "collected queries" },
        artifacts: [{ "kind" => "query_inventory", "data" => { "queries" => [{ "model" => "User", "query" => "User.all", "location" => "app/controllers/users_controller.rb:10" }] } }],
        trace_events: [trace_event("collected queries")]
      )
    end

    def analyze_performance_result
      AgentResult.success(
        report: { "summary" => "analyzed performance" },
        artifacts: [{ "kind" => "query_analysis", "data" => { "findings" => [{ "query" => "User.all", "issue" => "full table scan", "severity" => "high" }] } }],
        trace_events: [trace_event("analyzed performance")]
      )
    end

    def scan_coverage_result
      AgentResult.success(
        report: { "summary" => "scanned coverage" },
        artifacts: [{ "kind" => "coverage_map", "data" => { "files" => [{ "path" => "app/services/payment.rb", "coverage" => 0.0 }] } }],
        trace_events: [trace_event("scanned coverage")]
      )
    end

    def identify_gaps_result
      AgentResult.success(
        report: { "summary" => "identified gaps" },
        artifacts: [
          { "kind" => "test_plan", "data" => { "units" => [{ "file" => "app/services/payment.rb", "tests" => ["test payment processing"] }] } },
          { "kind" => "gap_analysis", "data" => { "platform_gaps" => [{ "area" => "alerting", "gap" => "no PagerDuty runbook" }] } }
        ],
        trace_events: [trace_event("identified gaps")]
      )
    end

    def scan_log_statements_result
      AgentResult.success(
        report: { "summary" => "scanned log statements" },
        artifacts: [{ "kind" => "log_inventory", "data" => { "statements" => [{ "file" => "app/controllers/orders_controller.rb", "line" => 3, "logger" => "puts", "level" => "unknown", "format" => "debug_output" }] } }],
        trace_events: [trace_event("scanned log statements")]
      )
    end

    def assess_quality_result
      AgentResult.success(
        report: { "summary" => "assessed quality" },
        artifacts: [{ "kind" => "logging_assessment", "data" => { "best_patterns" => [], "worst_offenders" => [], "scores_by_file" => {}, "recommended_standard" => {} } }],
        trace_events: [trace_event("assessed quality")]
      )
    end

    def draft_standard_result
      AgentResult.success(
        report: { "summary" => "drafted standard" },
        artifacts: [{ "kind" => "logging_standard", "data" => { "standard" => { "format" => "structured_json" } } }],
        trace_events: [trace_event("drafted standard")]
      )
    end

    def plan_disruption_result
      AgentResult.success(
        report: { "summary" => "planned disruption" },
        artifacts: [{ "kind" => "disruption_plan", "data" => { "scenario" => "kill database connection", "reversal_steps" => ["restart connection pool"] } }],
        trace_events: [trace_event("planned disruption")]
      )
    end

    def execute_disruption_result
      AgentResult.success(
        report: { "summary" => "executed disruption" },
        artifacts: [{ "kind" => "disruption_record", "data" => { "commands_run" => ["kill -9 postgres"] } }],
        trace_events: [trace_event("executed disruption")]
      )
    end

    def monitor_impact_result
      AgentResult.success(
        report: { "summary" => "monitored impact" },
        artifacts: [{ "kind" => "impact_report", "data" => { "affected_services" => ["api"], "error_rate_spike" => true } }],
        trace_events: [trace_event("monitored impact")]
      )
    end

    def evaluate_recovery_result
      AgentResult.success(
        report: { "summary" => "evaluated recovery" },
        artifacts: [{ "kind" => "recovery_evaluation", "data" => { "scores" => { "detection" => 8, "response" => 7, "recovery" => 9 } } }],
        trace_events: [trace_event("evaluated recovery")]
      )
    end

    def detect_alerts_result
      AgentResult.success(
        report: { "summary" => "detected alerts" },
        artifacts: [{ "kind" => "detected_alerts", "data" => { "events" => [{ "source" => "PagerDuty", "title" => "High error rate", "severity" => "critical" }] } }],
        trace_events: [trace_event("detected alerts")]
      )
    end

    def diagnose_failure_result
      AgentResult.success(
        report: { "summary" => "diagnosed failure" },
        artifacts: [{ "kind" => "diagnosis", "data" => { "root_cause_hypothesis" => "Database connection pool exhausted", "confidence" => "high" } }],
        trace_events: [trace_event("diagnosed failure")]
      )
    end

    def select_runbook_result
      AgentResult.success(
        report: { "summary" => "selected runbook" },
        artifacts: [{ "kind" => "runbook_selection", "data" => { "runbook" => "database-recovery", "reason" => "matches diagnosis" } }],
        trace_events: [trace_event("selected runbook")]
      )
    end

    def execute_runbook_result
      AgentResult.success(
        report: { "summary" => "executed runbook" },
        artifacts: [{ "kind" => "runbook_execution", "data" => { "steps_executed" => ["restart connection pool", "verify health"], "outcome" => "success" } }],
        trace_events: [trace_event("executed runbook")]
      )
    end

    def verify_recovery_result
      AgentResult.success(
        report: { "summary" => "verified recovery" },
        artifacts: [{ "kind" => "recovery_verification", "data" => { "service_healthy" => true, "checks" => { "api" => "passing", "database" => "passing" } } }],
        trace_events: [trace_event("verified recovery")]
      )
    end

    def scan_job_classes_result
      AgentResult.success(
        report: { "summary" => "scanned job classes" },
        artifacts: [{ "kind" => "job_inventory", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "queue" => "default" }] } }],
        trace_events: [trace_event("scanned job classes")]
      )
    end

    def assess_observability_result
      AgentResult.success(
        report: { "summary" => "assessed observability" },
        artifacts: [
          { "kind" => "job_inventory", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "queue" => "default" }] } },
          { "kind" => "observability_assessment", "data" => { "jobs" => [{ "class" => "ProcessPaymentJob", "has_logging" => false, "has_metrics" => false }] } }
        ],
        trace_events: [trace_event("assessed observability")]
      )
    end

    def inventory_services_result
      AgentResult.success(
        report: { "summary" => "inventoried services" },
        artifacts: [{ "kind" => "service_inventory", "data" => { "services" => [{ "name" => "api", "tier" => 1 }] } }],
        trace_events: [trace_event("inventoried services")]
      )
    end

    def score_readiness_result
      AgentResult.success(
        report: { "summary" => "scored readiness" },
        artifacts: [
          { "kind" => "service_inventory", "data" => { "services" => [{ "name" => "api", "tier" => 1 }] } },
          { "kind" => "readiness_scores", "data" => { "services" => [{ "name" => "api", "scores" => { "runbook" => 7 }, "total_score" => 7, "grade" => "C" }] } }
        ],
        trace_events: [trace_event("scored readiness")]
      )
    end

    def draft_improvements_result
      AgentResult.success(
        report: { "summary" => "drafted improvements" },
        artifacts: [{ "kind" => "improvement_drafts", "data" => { "improvements" => [{ "service" => "api", "files" => [{ "path" => "docs/runbooks/api.md", "content" => "# API Runbook" }] }] } }],
        trace_events: [trace_event("drafted improvements")]
      )
    end

    def scan_secrets_result
      AgentResult.success(
        report: { "summary" => "scanned secrets" },
        artifacts: [{ "kind" => "secret_inventory", "data" => { "secrets" => [{ "name" => "DATABASE_URL", "location" => ".env", "last_rotated" => "2024-01-01" }] } }],
        trace_events: [trace_event("scanned secrets")]
      )
    end

    def map_dependencies_result
      AgentResult.success(
        report: { "summary" => "mapped dependencies" },
        artifacts: [{ "kind" => "dependency_map", "data" => { "credentials" => [{ "name" => "DATABASE_URL", "consumers" => ["app/config/database.yml"] }] } }],
        trace_events: [trace_event("mapped dependencies")]
      )
    end

    def assess_risk_result
      AgentResult.success(
        report: { "summary" => "assessed risk" },
        artifacts: [{ "kind" => "risk_assessment", "data" => { "credentials" => [{ "name" => "DATABASE_URL", "risk" => "high" }], "summary" => { "high_risk_count" => 1 } } }],
        trace_events: [trace_event("assessed risk")]
      )
    end

    def draft_rotation_plan_result
      AgentResult.success(
        report: { "summary" => "drafted rotation plan" },
        artifacts: [{ "kind" => "rotation_plan", "data" => { "rotations" => [{ "credential" => "DATABASE_URL", "steps" => ["generate new password", "update vault", "restart app"] }] } }],
        trace_events: [trace_event("drafted rotation plan")]
      )
    end

    def audit_dependencies_result
      AgentResult.success(
        report: { "summary" => "audited dependencies" },
        artifacts: [{ "kind" => "dependency_audit", "data" => { "dependencies" => [{ "name" => "rack", "current" => "2.2.8", "latest" => "3.0.9", "outdated" => true }] } }],
        trace_events: [trace_event("audited dependencies")]
      )
    end

    def prioritize_upgrades_result
      AgentResult.success(
        report: { "summary" => "prioritized upgrades" },
        artifacts: [{ "kind" => "upgrade_plan", "data" => { "upgrades" => [{ "deps" => ["rack"], "priority" => 1, "risk" => "medium", "reason" => "CVE fix" }] } }],
        trace_events: [trace_event("prioritized upgrades")]
      )
    end

    def upgrade_one_result
      AgentResult.success(
        report: { "summary" => "upgraded one dependency" },
        artifacts: [{ "kind" => "upgrade_patches", "data" => { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "3.0.9", "patches" => [{ "file" => "Gemfile", "original" => "rack 2.2.8", "replacement" => "rack 3.0.9" }] } }],
        trace_events: [trace_event("upgraded one dependency")]
      )
    end

    def scan_impact_result
      AgentResult.success(
        report: { "summary" => "scanned impact" },
        artifacts: [{ "kind" => "impact_map", "data" => { "affected_files" => ["app/models/user.rb", "spec/models/user_spec.rb"] } }],
        trace_events: [trace_event("scanned impact")]
      )
    end

    def enumerate_risks_result
      AgentResult.success(
        report: { "summary" => "enumerated risks" },
        artifacts: [{ "kind" => "risk_assessment", "data" => { "risks" => [{ "description" => "table lock during migration", "severity" => "high" }] } }],
        trace_events: [trace_event("enumerated risks")]
      )
    end

    def draft_rollback_result
      AgentResult.success(
        report: { "summary" => "drafted rollback" },
        artifacts: [{ "kind" => "rollback_plan", "data" => { "procedures" => [{ "name" => "rollback migration", "steps" => [{ "action" => "run rollback migration", "command" => "rails db:rollback" }] }] } }],
        trace_events: [trace_event("drafted rollback")]
      )
    end

    def test_rollback_result
      AgentResult.success(
        report: { "summary" => "tested rollback" },
        artifacts: [{ "kind" => "rollback_test_results", "data" => { "migration_succeeded" => true, "rollback_succeeded" => true, "data_intact" => true, "health_checks_passed" => true } }],
        trace_events: [trace_event("tested rollback")]
      )
    end

    def scan_vulnerabilities_result
      AgentResult.success(
        report: { "summary" => "scanned vulnerabilities" },
        artifacts: [{ "kind" => "vulnerability_scan", "data" => { "vulnerabilities" => [{ "id" => "CVE-2024-0001", "severity" => "high", "package" => "rack" }] } }],
        trace_events: [trace_event("scanned vulnerabilities")]
      )
    end

    def define_rules_result
      AgentResult.success(
        report: { "summary" => "defined rules" },
        artifacts: [{ "kind" => "integrity_rules", "data" => { "rules" => [{ "name" => "no_orphan_work_items", "description" => "every work item belongs to a valid queue" }] } }],
        trace_events: [trace_event("defined rules")]
      )
    end

    def scan_violations_result
      AgentResult.success(
        report: { "summary" => "scanned violations" },
        artifacts: [{ "kind" => "violation_report", "data" => { "results" => [{ "rule" => "no_orphan_work_items", "violations" => 0 }] } }],
        trace_events: [trace_event("scanned violations")]
      )
    end

    def assess_damage_result
      AgentResult.success(
        report: { "summary" => "assessed damage" },
        artifacts: [{ "kind" => "damage_assessment", "data" => { "findings" => [{ "table" => "work_items", "severity" => "low", "description" => "minor inconsistency" }] } }],
        trace_events: [trace_event("assessed damage")]
      )
    end

    def draft_repairs_result
      AgentResult.success(
        report: { "summary" => "drafted repairs" },
        artifacts: [{ "kind" => "repair_scripts", "data" => { "repairs" => [{ "name" => "fix_orphans", "sql" => "DELETE FROM work_items WHERE work_queue_id IS NULL" }] } }],
        trace_events: [trace_event("drafted repairs")]
      )
    end

    def ingest_artifacts_result
      AgentResult.success(
        report: { "summary" => "ingested artifacts" },
        artifacts: [{ "kind" => "incident_artifacts", "data" => { "sentry_events" => [{ "id" => "abc123", "title" => "NoMethodError in PaymentService" }], "slack_messages" => [], "deploys" => [] } }],
        trace_events: [trace_event("ingested artifacts")]
      )
    end

    def reconstruct_timeline_result
      AgentResult.success(
        report: { "summary" => "reconstructed timeline" },
        artifacts: [{ "kind" => "incident_timeline", "data" => { "phases" => [{ "name" => "detection", "start" => "2024-01-01T00:00:00Z", "end" => "2024-01-01T00:05:00Z" }], "total_duration_minutes" => 45 } }],
        trace_events: [trace_event("reconstructed timeline")]
      )
    end

    def analyze_root_cause_result
      AgentResult.success(
        report: { "summary" => "analyzed root cause" },
        artifacts: [{ "kind" => "root_cause_analysis", "data" => { "root_cause" => "Memory leak in payment processor under high load", "contributing_factors" => ["no memory limit set"] } }],
        trace_events: [trace_event("analyzed root cause")]
      )
    end

    def evaluate_response_result
      AgentResult.success(
        report: { "summary" => "evaluated response" },
        artifacts: [{ "kind" => "response_evaluation", "data" => { "grade" => "B", "strengths" => ["fast detection"], "weaknesses" => ["slow remediation"] } }],
        trace_events: [trace_event("evaluated response")]
      )
    end

    def draft_updates_result
      AgentResult.success(
        report: { "summary" => "drafted updates" },
        artifacts: [{ "kind" => "incident_updates", "data" => { "runbook_updates" => [{ "runbook" => "database-recovery", "update" => "Add connection pool check step" }], "new_alerts" => [] } }],
        trace_events: [trace_event("drafted updates")]
      )
    end

    def collect_configs_result
      AgentResult.success(
        report: { "summary" => "collected configs" },
        artifacts: [{ "kind" => "environment_configs", "data" => { "environments" => { "production" => { "database_pool" => 5, "log_level" => "warn" }, "staging" => { "database_pool" => 2, "log_level" => "debug" } } } }],
        trace_events: [trace_event("collected configs")]
      )
    end

    def diff_environments_result
      AgentResult.success(
        report: { "summary" => "diffed environments" },
        artifacts: [{ "kind" => "environment_diff", "data" => { "comparisons" => [{ "key" => "database_pool", "production" => 5, "staging" => 2, "drift" => true }] } }],
        trace_events: [trace_event("diffed environments")]
      )
    end

    def classify_drift_result
      AgentResult.success(
        report: { "summary" => "classified drift" },
        artifacts: [{ "kind" => "drift_classification", "data" => { "drifts" => [{ "key" => "database_pool", "severity" => "medium", "action" => "sync_staging" }] } }],
        trace_events: [trace_event("classified drift")]
      )
    end

    def draft_sync_plan_result
      AgentResult.success(
        report: { "summary" => "drafted sync plan" },
        artifacts: [{ "kind" => "sync_plan", "data" => { "actions" => [{ "environment" => "staging", "key" => "database_pool", "from" => 2, "to" => 5, "command" => "set DATABASE_POOL=5" }] } }],
        trace_events: [trace_event("drafted sync plan")]
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

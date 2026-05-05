module Engine
  class PredicateRegistry
    class UnknownPredicate < StandardError; end

    PREDICATES = {
      "report_present" => Predicates::ReportPresent,
      "branch_created" => Predicates::BranchCreated,
      "tests_passed" => Predicates::TestsPassed,
      "lint_clean" => Predicates::LintClean,
      "coverage_not_decreased" => Predicates::CoverageNotDecreased,
      "review_verdict" => Predicates::ReviewVerdict,
      "clusters_created" => Predicates::ClustersCreated,
      "assessment_complete" => Predicates::AssessmentComplete,
      "error_patterns_found" => Predicates::ErrorPatternsFound,
      "severity_classified" => Predicates::SeverityClassified,
      "fixes_drafted" => Predicates::FixesDrafted,
      "runbook_mapped" => Predicates::RunbookMapped,
      "runbook_drafted" => Predicates::RunbookDrafted,
      "validation_passed" => Predicates::ValidationPassed,
      "coverage_map_produced" => Predicates::CoverageMapProduced,
      "test_plan_produced" => Predicates::TestPlanProduced,
      "tests_generated" => Predicates::TestsGenerated,
      "endpoint_inventory_produced" => Predicates::EndpointInventoryProduced,
      "docs_diff_produced" => Predicates::DocsDiffProduced,
      "docs_drafted" => Predicates::DocsDrafted,
      "docs_validated" => Predicates::DocsValidated,
      "query_inventory_produced" => Predicates::QueryInventoryProduced,
      "query_analyzed" => Predicates::QueryAnalyzed,
      "query_fixes_drafted" => Predicates::QueryFixesDrafted,
      "log_inventory_produced" => Predicates::LogInventoryProduced,
      "logging_assessed" => Predicates::LoggingAssessed,
      "standard_drafted" => Predicates::StandardDrafted,
      "job_inventory_produced" => Predicates::JobInventoryProduced,
      "observability_assessed" => Predicates::ObservabilityAssessed,
      "disruption_planned" => Predicates::DisruptionPlanned,
      "disruption_executed" => Predicates::DisruptionExecuted,
      "impact_observed" => Predicates::ImpactObserved,
      "recovery_evaluated" => Predicates::RecoveryEvaluated,
      "alerts_detected" => Predicates::AlertsDetected,
      "diagnosis_produced" => Predicates::DiagnosisProduced,
      "runbook_selected" => Predicates::RunbookSelected,
      "runbook_executed" => Predicates::RunbookExecuted,
      "recovery_verified" => Predicates::RecoveryVerified,
      "service_inventory_produced" => Predicates::ServiceInventoryProduced,
      "readiness_scored" => Predicates::ReadinessScored,
      "gaps_identified" => Predicates::GapsIdentified,
      "improvements_drafted" => Predicates::ImprovementsDrafted
    }.freeze

    def self.resolve(name)
      PREDICATES.fetch(name) { raise UnknownPredicate, "unknown predicate: #{name}" }
    end
  end
end

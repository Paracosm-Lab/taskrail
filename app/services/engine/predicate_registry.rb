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
      "runbook_mapped" => Predicates::RunbookMapped,
      "runbook_drafted" => Predicates::RunbookDrafted,
      "validation_passed" => Predicates::ValidationPassed
    }.freeze

    def self.resolve(name)
      PREDICATES.fetch(name) { raise UnknownPredicate, "unknown predicate: #{name}" }
    end
  end
end

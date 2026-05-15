module Engine
  module Predicates
    class CoverageChecked
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "coverage_report").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing coverage_report artifact") unless artifact

        changed_files = artifact.data["changed_files"]
        return PredicateResult.fail(reason: "coverage_report changed_files must be an array") unless changed_files.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            changed_files_count: changed_files.count,
            new_files_without_tests_count: Array(artifact.data["new_files_without_tests"]).count
          }
        )
      end
    end
  end
end

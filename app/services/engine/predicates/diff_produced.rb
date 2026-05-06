module Engine
  module Predicates
    class DiffProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "environment_diff").first
        return PredicateResult.fail(reason: "missing environment_diff artifact") unless artifact

        comparisons = artifact.data["comparisons"]
        return PredicateResult.fail(reason: "environment_diff artifact has no comparisons array") unless comparisons.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            comparison_count: comparisons.count
          }
        )
      end
    end
  end
end

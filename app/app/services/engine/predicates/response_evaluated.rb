module Engine
  module Predicates
    class ResponseEvaluated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "response_evaluation").first
        return PredicateResult.fail(reason: "missing response_evaluation artifact") unless artifact

        grade = artifact.data["grade"]
        return PredicateResult.fail(reason: "response_evaluation artifact missing grade key") unless grade

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            grade: grade
          }
        )
      end
    end
  end
end

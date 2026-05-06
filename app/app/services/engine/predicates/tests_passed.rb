module Engine
  module Predicates
    class TestsPassed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "test_results").detect { |item| item.data["passed"] == true }
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing passing test_results artifact")
      end
    end
  end
end

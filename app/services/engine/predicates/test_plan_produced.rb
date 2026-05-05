module Engine
  module Predicates
    class TestPlanProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "test_plan").detect do |item|
          item.data["units"].is_a?(Array) && item.data["units"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing test_plan artifact with units")
      end
    end
  end
end

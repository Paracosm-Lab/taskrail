module Engine
  module Predicates
    class TestsGenerated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "generated_tests").detect do |item|
          item.data["specs"].is_a?(Array) && item.data["specs"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing generated_tests artifact with specs")
      end
    end
  end
end

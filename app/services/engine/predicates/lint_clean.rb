module Engine
  module Predicates
    class LintClean
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "lint").detect { |item| item.data["clean"] == true }
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing clean lint artifact")
      end
    end
  end
end

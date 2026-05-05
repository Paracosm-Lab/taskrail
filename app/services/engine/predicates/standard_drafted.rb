module Engine
  module Predicates
    class StandardDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "logging_standard").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no logging standard artifact found")
      end
    end
  end
end

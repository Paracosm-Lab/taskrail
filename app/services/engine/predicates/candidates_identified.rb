module Engine
  module Predicates
    class CandidatesIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "removal_candidates").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing removal_candidates artifact")
      end
    end
  end
end

module Engine
  module Predicates
    class ClustersCreated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "clusters").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no clusters artifact found")
      end
    end
  end
end

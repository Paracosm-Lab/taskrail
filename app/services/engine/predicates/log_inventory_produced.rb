module Engine
  module Predicates
    class LogInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "log_inventory").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no log inventory artifact found")
      end
    end
  end
end

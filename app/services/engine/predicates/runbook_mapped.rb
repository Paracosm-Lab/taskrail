module Engine
  module Predicates
    class RunbookMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "runbook_mapping").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no runbook mapping artifact found")
      end
    end
  end
end

module Engine
  module Predicates
    class RunbookDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "runbook_draft").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no runbook draft artifact found")
      end
    end
  end
end

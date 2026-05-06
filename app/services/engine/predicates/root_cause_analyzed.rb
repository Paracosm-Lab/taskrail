module Engine
  module Predicates
    class RootCauseAnalyzed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "root_cause_analysis").first
        return PredicateResult.fail(reason: "missing root_cause_analysis artifact") unless artifact

        root_cause = artifact.data["root_cause"]
        return PredicateResult.fail(reason: "root_cause_analysis artifact missing root_cause key") unless root_cause

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            root_cause_present: true
          }
        )
      end
    end
  end
end

module Engine
  module Predicates
    class DriftClassified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "drift_classification").first
        return PredicateResult.fail(reason: "missing drift_classification artifact") unless artifact

        drifts = artifact.data["drifts"]
        return PredicateResult.fail(reason: "drift_classification artifact has no drifts array") unless drifts.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            drift_count: drifts.count
          }
        )
      end
    end
  end
end

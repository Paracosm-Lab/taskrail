module Engine
  module Predicates
    class RiskAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "risk_assessment").first
        return PredicateResult.fail(reason: "missing risk_assessment artifact") unless artifact

        credentials = artifact.data["credentials"]
        return PredicateResult.fail(reason: "risk_assessment artifact has no credentials array") unless credentials.is_a?(Array)
        return PredicateResult.fail(reason: "risk_assessment artifact has no summary") if artifact.data["summary"].blank?

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            critical_count: artifact.data.fetch("critical_count", 0),
            credential_count: credentials.count
          }
        )
      end
    end
  end
end

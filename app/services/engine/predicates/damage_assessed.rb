module Engine
  module Predicates
    class DamageAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "damage_assessment").first
        return PredicateResult.fail(reason: "missing damage_assessment artifact") unless artifact

        findings = artifact.data["findings"]
        return PredicateResult.fail(reason: "damage_assessment artifact has no findings array") unless findings.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            finding_count: findings.count
          }
        )
      end
    end
  end
end

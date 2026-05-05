module Engine
  module Predicates
    class RisksEnumerated
      ALLOWED_SEVERITIES = %w[blocking high medium low].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "risk_assessment").first
        return PredicateResult.fail(reason: "no risk_assessment artifact found") unless artifact

        risks = artifact.data["risks"]
        return PredicateResult.fail(reason: "risk_assessment artifact has no risks") unless risks.is_a?(Array) && risks.any?
        return PredicateResult.fail(reason: "risk_assessment contains unknown severity") if risks.any? { |risk| !ALLOWED_SEVERITIES.include?(risk["severity"]) }

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          risks_count: risks.count,
          blocking_risks_count: Array(artifact.data["blocking_risks"]).count
        })
      end
    end
  end
end

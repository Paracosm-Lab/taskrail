module Engine
  module Predicates
    class SeverityClassified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "severity_report").first
        return PredicateResult.fail(reason: "no severity_report artifact found") unless artifact

        findings = artifact.data.fetch("findings", [])
        return PredicateResult.fail(reason: "severity_report artifact has no findings") if findings.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, finding_count: findings.count })
      end
    end
  end
end

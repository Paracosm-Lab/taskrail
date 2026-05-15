module Engine
  module Predicates
    class SecurityReviewed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "security_findings").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing security_findings artifact") unless artifact

        findings = Array(artifact.data["findings"])
        blocking_count = artifact.data.fetch("blocking_count", findings.count { |finding| finding["severity"] == "blocking" }).to_i
        return PredicateResult.fail(reason: "blocking security findings: #{blocking_count}") if blocking_count.positive?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, findings_count: findings.count, blocking_count: blocking_count })
      end
    end
  end
end

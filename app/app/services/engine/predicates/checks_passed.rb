module Engine
  module Predicates
    class ChecksPassed
      REQUIRED_CHECKS = %w[lint tests build].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "check_results").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing check_results artifact") unless artifact

        failed = REQUIRED_CHECKS.reject { |name| artifact.data.dig(name, "passed") == true }
        return PredicateResult.fail(reason: "PR checks failed: #{failed.join(", ")}") if failed.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, checks: REQUIRED_CHECKS })
      end
    end
  end
end

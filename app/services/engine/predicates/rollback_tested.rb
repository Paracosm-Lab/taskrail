module Engine
  module Predicates
    class RollbackTested
      REQUIRED_TRUE_KEYS = %w[migration_succeeded rollback_succeeded data_intact health_checks_passed].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rollback_test_results").first
        return PredicateResult.fail(reason: "no rollback_test_results artifact found") unless artifact

        failed_keys = REQUIRED_TRUE_KEYS.reject { |key| artifact.data[key] == true }
        return PredicateResult.fail(reason: "rollback_test_results has failed checks: #{failed_keys.join(', ')}") if failed_keys.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id })
      end
    end
  end
end

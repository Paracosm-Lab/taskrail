module Engine
  module Predicates
    class RollbackDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rollback_plan").first
        return PredicateResult.fail(reason: "no rollback_plan artifact found") unless artifact

        procedures = artifact.data["procedures"]
        return PredicateResult.fail(reason: "rollback_plan artifact has no procedures") unless procedures.is_a?(Array) && procedures.any?

        steps_count = procedures.sum { |procedure| Array(procedure["steps"]).count }
        return PredicateResult.fail(reason: "rollback_plan procedures require testable steps") if steps_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, procedures_count: procedures.count, steps_count: steps_count })
      end
    end
  end
end

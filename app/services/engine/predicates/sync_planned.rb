module Engine
  module Predicates
    class SyncPlanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "sync_plan").first
        return PredicateResult.fail(reason: "missing sync_plan artifact") unless artifact

        actions = artifact.data["actions"]
        return PredicateResult.fail(reason: "sync_plan artifact has no actions array") unless actions.is_a?(Array)
        return PredicateResult.fail(reason: "sync_plan artifact has empty actions array") if actions.empty?

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            action_count: actions.count
          }
        )
      end
    end
  end
end

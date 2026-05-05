module Engine
  module Predicates
    class RecoveryEvaluated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("recovery_evaluation")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["scores"].present?

        PredicateResult.fail(reason: "recovery_evaluation missing scores")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

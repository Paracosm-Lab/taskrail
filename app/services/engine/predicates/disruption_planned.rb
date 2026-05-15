module Engine
  module Predicates
    class DisruptionPlanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("disruption_plan")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["scenario"].present? && data["reversal_steps"].present?

        PredicateResult.fail(reason: "disruption_plan missing scenario or reversal_steps")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

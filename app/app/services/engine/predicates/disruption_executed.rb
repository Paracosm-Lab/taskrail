module Engine
  module Predicates
    class DisruptionExecuted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("disruption_record")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["commands_run"].present?

        PredicateResult.fail(reason: "disruption_record missing commands_run")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

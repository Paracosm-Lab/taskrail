module Engine
  module Predicates
    class RunbookExecuted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("runbook_execution")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data.key?("steps_executed")

        PredicateResult.fail(reason: "runbook_execution missing steps_executed")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

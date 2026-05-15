module Engine
  module Predicates
    class RunbookSelected
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("runbook_selection")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact.present?

        PredicateResult.fail(reason: "missing runbook_selection artifact")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

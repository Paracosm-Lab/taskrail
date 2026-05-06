module Engine
  module Predicates
    class ImpactObserved
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("impact_report")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact.present?

        PredicateResult.fail(reason: "missing impact_report artifact")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

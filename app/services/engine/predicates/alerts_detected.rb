module Engine
  module Predicates
    class AlertsDetected
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("detected_alerts")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["events"].present?

        PredicateResult.fail(reason: "detected_alerts missing events")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

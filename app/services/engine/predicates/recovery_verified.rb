module Engine
  module Predicates
    class RecoveryVerified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("recovery_verification")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["service_healthy"] == true

        PredicateResult.fail(reason: "recovery_verification service_healthy is not true")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

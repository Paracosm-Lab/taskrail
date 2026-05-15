module Engine
  module Predicates
    class DiagnosisProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("diagnosis")
        data = artifact&.data || {}

        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if data["root_cause_hypothesis"].present?

        PredicateResult.fail(reason: "diagnosis missing root_cause_hypothesis")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end

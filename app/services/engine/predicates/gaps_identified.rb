module Engine
  module Predicates
    class GapsIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "gap_analysis").detect do |item|
          Array(item.data["platform_gaps"]).any? ||
            Array(item.data["service_gaps"]).any? ||
            Array(item.data["priority_order"]).any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing non-empty gap_analysis artifact")
      end
    end
  end
end

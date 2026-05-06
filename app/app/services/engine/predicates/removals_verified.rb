module Engine
  module Predicates
    class RemovalsVerified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "verified_removals").detect do |item|
          safe_to_remove_count(item).positive?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, safe_to_remove_count: safe_to_remove_count(artifact) }) if artifact

        PredicateResult.fail(reason: "missing verified_removals artifact with safe_to_remove removals")
      end

      private

      def safe_to_remove_count(artifact)
        Array(artifact.data["removals"]).count { |removal| removal["classification"] == "safe_to_remove" }
      end
    end
  end
end

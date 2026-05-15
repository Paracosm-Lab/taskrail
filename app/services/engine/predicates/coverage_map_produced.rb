module Engine
  module Predicates
    class CoverageMapProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "coverage_map").detect do |item|
          item.data["files"].is_a?(Array) && item.data["files"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing coverage_map artifact with files")
      end
    end
  end
end

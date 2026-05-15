module Engine
  module Predicates
    class ErrorPatternsFound
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "error_patterns").first
        return PredicateResult.fail(reason: "no error_patterns artifact found") unless artifact

        patterns = artifact.data.fetch("patterns", [])
        PredicateResult.pass(evidence: { artifact_id: artifact.id, pattern_count: patterns.count })
      end
    end
  end
end

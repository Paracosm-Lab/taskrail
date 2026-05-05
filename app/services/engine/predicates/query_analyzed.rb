module Engine
  module Predicates
    class QueryAnalyzed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_analysis").first
        return PredicateResult.fail(reason: "no query_analysis artifact found") unless artifact

        finding_count = Array(artifact.data["findings"]).count
        return PredicateResult.fail(reason: "query_analysis artifact has no findings") if finding_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, finding_count: finding_count })
      end
    end
  end
end

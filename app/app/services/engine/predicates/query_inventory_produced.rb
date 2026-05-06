module Engine
  module Predicates
    class QueryInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_inventory").first
        return PredicateResult.fail(reason: "no query_inventory artifact found") unless artifact

        query_count = Array(artifact.data["queries"]).count
        return PredicateResult.fail(reason: "query_inventory artifact has no queries") if query_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, query_count: query_count })
      end
    end
  end
end

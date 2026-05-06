module Engine
  module Predicates
    class ServiceInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "service_inventory").detect do |item|
          item.data["services"].is_a?(Array) && item.data["services"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing service_inventory artifact with services")
      end
    end
  end
end

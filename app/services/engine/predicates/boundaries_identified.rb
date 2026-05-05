module Engine
  module Predicates
    class BoundariesIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "boundary_map").order(created_at: :desc, id: :desc).first
        return PredicateResult.fail(reason: "no boundary_map artifact found") unless artifact

        flows = artifact.data["flows"]
        return PredicateResult.fail(reason: "boundary_map artifact has no flows") unless flows.is_a?(Array) && flows.any?

        flows_without_boundaries = flows.select { |flow| Array(flow["boundaries"]).empty? }
        if flows_without_boundaries.any?
          names = flows_without_boundaries.map { |flow| flow["name"].presence || "unnamed flow" }.join(", ")
          return PredicateResult.fail(reason: "boundary_map artifact has flows without boundaries: #{names}")
        end

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            flows_count: flows.count,
            boundaries_count: flows.sum { |flow| Array(flow["boundaries"]).count }
          }
        )
      end
    end
  end
end

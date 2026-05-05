module Engine
  module Predicates
    class ReadinessScored
      def initialize(claim:)
        @claim = claim
      end

      def call
        inventory = @claim.artifacts.where(kind: "service_inventory").order(created_at: :desc).first
        scores = @claim.artifacts.where(kind: "readiness_scores").order(created_at: :desc).first
        return PredicateResult.fail(reason: "readiness_scores missing scores for inventoried services") unless inventory && scores

        inventoried_names = Array(inventory.data["services"]).filter_map { |service| service["name"] }
        scored_names = Array(scores.data["services"]).filter_map do |service|
          service["name"] if service["scores"].is_a?(Hash) && service.key?("total_score") && service["grade"].present?
        end

        if inventoried_names.any? && (inventoried_names - scored_names).empty?
          PredicateResult.pass(evidence: { artifact_id: scores.id })
        else
          PredicateResult.fail(reason: "readiness_scores missing scores for inventoried services")
        end
      end
    end
  end
end

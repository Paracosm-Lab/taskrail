module Engine
  module Predicates
    class FlowsMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "user_flows").order(created_at: :desc, id: :desc).first
        return PredicateResult.fail(reason: "no user_flows artifact found") unless artifact

        flows = artifact.data["flows"]
        return PredicateResult.fail(reason: "user_flows artifact has no flows") unless flows.is_a?(Array) && flows.any?

        flows_without_steps = flows.select { |flow| Array(flow["steps"]).empty? }
        if flows_without_steps.any?
          names = flows_without_steps.map { |flow| flow["name"].presence || "unnamed flow" }.join(", ")
          return PredicateResult.fail(reason: "user_flows artifact has flows without steps: #{names}")
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, flows_count: flows.count })
      end
    end
  end
end

module Engine
  module Predicates
    class EndpointInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        artifact = artifact_from(report)
        return PredicateResult.fail(reason: "endpoint inventory artifact missing") unless artifact

        endpoints = artifact["endpoints"]
        return PredicateResult.fail(reason: "endpoint inventory has no endpoints") unless endpoints.is_a?(Array) && endpoints.any?

        PredicateResult.pass(evidence: { report_id: report.id, endpoint_count: endpoints.size })
      end

      private

      def artifact_from(report)
        return unless report&.body.is_a?(Hash)
        return report.body["endpoint_inventory"] if report.body["endpoint_inventory"].is_a?(Hash)
        return report.body["artifact"] if report.body["artifact_kind"] == "endpoint_inventory" && report.body["artifact"].is_a?(Hash)
      end
    end
  end
end

module Engine
  module Predicates
    class DocsDiffProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        artifact = artifact_from(report)
        return PredicateResult.fail(reason: "docs diff artifact missing") unless artifact

        PredicateResult.pass(evidence: {
          report_id: report.id,
          missing_count: Array(artifact["missing"]).size,
          stale_count: Array(artifact["stale"]).size,
          incorrect_count: Array(artifact["incorrect"]).size
        })
      end

      private

      def artifact_from(report)
        return unless report&.body.is_a?(Hash)
        return report.body["docs_diff"] if report.body["docs_diff"].is_a?(Hash)
        return report.body["artifact"] if report.body["artifact_kind"] == "docs_diff" && report.body["artifact"].is_a?(Hash)
      end
    end
  end
end

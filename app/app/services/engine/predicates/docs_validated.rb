module Engine
  module Predicates
    class DocsValidated
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        artifact = artifact_from(report)
        return PredicateResult.fail(reason: "validation results artifact missing") unless artifact

        errors = Array(artifact["errors"])
        unless artifact["valid"] == true
          reason = "API docs validation failed"
          reason = "#{reason}: #{errors.first}" if errors.first
          return PredicateResult.fail(reason: reason)
        end

        PredicateResult.pass(evidence: { report_id: report.id, error_count: errors.size })
      end

      private

      def artifact_from(report)
        return unless report&.body.is_a?(Hash)
        return report.body["validation_results"] if report.body["validation_results"].is_a?(Hash)
        return report.body["artifact"] if report.body["artifact_kind"] == "validation_results" && report.body["artifact"].is_a?(Hash)
      end
    end
  end
end

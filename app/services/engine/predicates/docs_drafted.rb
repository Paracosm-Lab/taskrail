module Engine
  module Predicates
    class DocsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        artifact = artifact_from(report)
        return PredicateResult.fail(reason: "draft docs artifact missing") unless artifact

        files = artifact["files"]
        return PredicateResult.fail(reason: "draft docs has no files") unless files.is_a?(Array) && files.any?

        PredicateResult.pass(evidence: { report_id: report.id, file_count: files.size, format: artifact["format"] })
      end

      private

      def artifact_from(report)
        return unless report&.body.is_a?(Hash)
        return report.body["draft_docs"] if report.body["draft_docs"].is_a?(Hash)
        return report.body["artifact"] if report.body["artifact_kind"] == "draft_docs" && report.body["artifact"].is_a?(Hash)
      end
    end
  end
end

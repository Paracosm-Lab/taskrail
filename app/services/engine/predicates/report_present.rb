module Engine
  module Predicates
    class ReportPresent
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.first
        return PredicateResult.pass(evidence: { report_id: report.id }) if report

        PredicateResult.fail(reason: "missing success report")
      end
    end
  end
end

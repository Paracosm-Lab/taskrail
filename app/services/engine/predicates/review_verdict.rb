module Engine
  module Predicates
    class ReviewVerdict
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.detect { |item| item.body["verdict"] == "approved" }
        return PredicateResult.pass(evidence: { report_id: report.id }) if report

        PredicateResult.fail(reason: "missing approved review verdict")
      end
    end
  end
end

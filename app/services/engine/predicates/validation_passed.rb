module Engine
  module Predicates
    class ValidationPassed
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        if report&.body&.dig("validation_passed") == true
          PredicateResult.pass(evidence: { report_id: report.id })
        else
          PredicateResult.fail(reason: "staging validation did not pass")
        end
      end
    end
  end
end

module Engine
  module Predicates
    class ViolationsScanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "violation_report").first
        return PredicateResult.fail(reason: "missing violation_report artifact") unless artifact

        results = artifact.data["results"]
        return PredicateResult.fail(reason: "violation_report artifact has no results array") unless results.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            violation_count: results.count
          }
        )
      end
    end
  end
end

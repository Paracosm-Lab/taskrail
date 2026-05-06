module Engine
  module Predicates
    class AssessmentComplete
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "instrumentation_assessment").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no instrumentation assessment artifact found")
      end
    end
  end
end

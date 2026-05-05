module Engine
  module Predicates
    class LoggingAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "logging_assessment").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no logging assessment artifact found")
      end
    end
  end
end

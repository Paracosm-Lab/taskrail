module Engine
  module Predicates
    class CoverageNotDecreased
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "coverage").detect do |item|
          current = item.data["current"]
          previous = item.data["previous"]
          current.present? && previous.present? && current.to_f >= previous.to_f
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        any_coverage = @claim.artifacts.where(kind: "coverage").exists?
        PredicateResult.fail(reason: any_coverage ? "coverage decreased" : "missing coverage artifact")
      end
    end
  end
end

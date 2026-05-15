module Engine
  module Predicates
    class TestsGenerated
      ACCEPTED_KINDS = %w[generated_tests integration_specs].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: ACCEPTED_KINDS).order(created_at: :desc, id: :desc).detect do |item|
          item.data["specs"].is_a?(Array) && item.data["specs"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, artifact_kind: artifact.kind, specs_count: artifact.data["specs"].count }) if artifact

        PredicateResult.fail(reason: "missing generated_tests or integration_specs artifact with specs")
      end
    end
  end
end

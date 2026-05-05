module Engine
  module Predicates
    class RotationPlanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rotation_plan").first
        return PredicateResult.fail(reason: "missing rotation_plan artifact") unless artifact

        rotations = artifact.data["rotations"]
        return PredicateResult.fail(reason: "rotation_plan artifact has no rotations") unless rotations.is_a?(Array) && rotations.any?
        return PredicateResult.fail(reason: "rotation_plan rotations are missing steps") unless rotations.all? { |rotation| rotation["steps"].is_a?(Array) && rotation["steps"].any? }

        PredicateResult.pass(evidence: { artifact_id: artifact.id, rotations_count: rotations.count })
      end
    end
  end
end

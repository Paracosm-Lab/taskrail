module Engine
  module Predicates
    class RepairsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "repair_scripts").first
        return PredicateResult.fail(reason: "missing repair_scripts artifact") unless artifact

        repairs = artifact.data["repairs"]
        return PredicateResult.fail(reason: "repair_scripts artifact has no repairs array") unless repairs.is_a?(Array)
        return PredicateResult.fail(reason: "repair_scripts artifact has empty repairs array") if repairs.empty?

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            repair_count: repairs.count
          }
        )
      end
    end
  end
end

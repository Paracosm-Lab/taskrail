module Engine
  module Predicates
    class RulesDefined
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "integrity_rules").first
        return PredicateResult.fail(reason: "missing integrity_rules artifact") unless artifact

        rules = artifact.data["rules"]
        return PredicateResult.fail(reason: "integrity_rules artifact has no rules array") unless rules.is_a?(Array)
        return PredicateResult.fail(reason: "integrity_rules artifact has empty rules array") if rules.empty?

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            rule_count: rules.count
          }
        )
      end
    end
  end
end

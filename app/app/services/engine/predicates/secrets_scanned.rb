module Engine
  module Predicates
    class SecretsScanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "secret_inventory").first
        return PredicateResult.fail(reason: "missing secret_inventory artifact") unless artifact

        secrets = artifact.data["secrets"]
        return PredicateResult.fail(reason: "secret_inventory artifact has no secrets array") unless secrets.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            total_count: artifact.data.fetch("total_count", secrets.count),
            hardcoded_count: artifact.data.fetch("hardcoded_count", 0)
          }
        )
      end
    end
  end
end

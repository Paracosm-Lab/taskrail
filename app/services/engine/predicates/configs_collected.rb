module Engine
  module Predicates
    class ConfigsCollected
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "environment_configs").first
        return PredicateResult.fail(reason: "missing environment_configs artifact") unless artifact

        environments = artifact.data["environments"]
        return PredicateResult.fail(reason: "environment_configs artifact has no environments key") unless environments.is_a?(Hash)
        return PredicateResult.fail(reason: "environment_configs artifact needs at least 2 environments") unless environments.keys.count >= 2

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            environment_count: environments.keys.count,
            environments: environments.keys
          }
        )
      end
    end
  end
end

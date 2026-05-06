module Engine
  module Predicates
    class ImpactMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "impact_map").first
        return PredicateResult.fail(reason: "no impact_map artifact found") unless artifact

        affected_files = Array(artifact.data["affected_files"])
        return PredicateResult.fail(reason: "impact_map artifact has no affected files") if affected_files.empty?

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          affected_files_count: affected_files.count,
          affected_tests_count: Array(artifact.data["affected_tests"]).count,
          affected_configs_count: Array(artifact.data["affected_configs"]).count,
          external_consumers_count: Array(artifact.data["external_consumers"]).count
        })
      end
    end
  end
end

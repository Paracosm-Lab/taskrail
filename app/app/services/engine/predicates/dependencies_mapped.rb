module Engine
  module Predicates
    class DependenciesMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "dependency_map").first
        return PredicateResult.fail(reason: "missing dependency_map artifact") unless artifact

        credentials = artifact.data["credentials"]
        return PredicateResult.fail(reason: "dependency_map artifact has no credentials array") unless credentials.is_a?(Array)

        PredicateResult.pass(evidence: { artifact_id: artifact.id, credential_count: credentials.count })
      end
    end
  end
end

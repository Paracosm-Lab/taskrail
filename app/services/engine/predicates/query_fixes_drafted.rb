module Engine
  module Predicates
    class QueryFixesDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_patches").first
        return PredicateResult.fail(reason: "no query_patches artifact found") unless artifact

        migration_count = Array(artifact.data["migrations"]).count
        code_patch_count = Array(artifact.data["code_patches"]).count
        if migration_count.zero? && code_patch_count.zero?
          return PredicateResult.fail(reason: "query_patches artifact has no migrations or code patches")
        end

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          migration_count: migration_count,
          code_patch_count: code_patch_count
        })
      end
    end
  end
end

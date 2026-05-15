module Engine
  module Predicates
    class RemovalsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "removal_patches").detect do |item|
          patch_count(item).positive?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, patch_count: patch_count(artifact) }) if artifact

        PredicateResult.fail(reason: "missing removal_patches artifact with patches")
      end

      private

      def patch_count(artifact)
        Array(artifact.data["patches"]).count
      end
    end
  end
end

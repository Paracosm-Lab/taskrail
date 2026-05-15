module Engine
  module Predicates
    class FixesDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "fix_patches").first
        return PredicateResult.fail(reason: "no fix_patches artifact found") unless artifact

        patches = artifact.data.fetch("patches", [])
        return PredicateResult.fail(reason: "fix_patches artifact has no patches") if patches.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, patch_count: patches.count })
      end
    end
  end
end

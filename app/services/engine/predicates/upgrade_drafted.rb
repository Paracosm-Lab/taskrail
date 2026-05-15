module Engine
  module Predicates
    class UpgradeDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "upgrade_patches").first
        return PredicateResult.fail(reason: "no upgrade_patches artifact found") unless artifact

        dep_name = artifact.data["dep_name"].to_s
        return PredicateResult.fail(reason: "upgrade_patches artifact is missing dep_name") if dep_name.empty?

        from_version = artifact.data["from_version"].to_s
        to_version = artifact.data["to_version"].to_s
        return PredicateResult.fail(reason: "upgrade_patches artifact has no version change") if from_version.empty? || to_version.empty? || from_version == to_version

        patches = Array(artifact.data["patches"])
        return PredicateResult.fail(reason: "upgrade_patches artifact has no patches") if patches.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, dep_name: dep_name, patch_count: patches.count })
      end
    end
  end
end

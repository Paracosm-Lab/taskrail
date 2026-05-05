module Engine
  module Predicates
    class UpgradePlanProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "upgrade_plan").first
        return PredicateResult.fail(reason: "no upgrade_plan artifact found") unless artifact

        upgrades = Array(artifact.data["upgrades"])
        return PredicateResult.fail(reason: "upgrade_plan artifact has no upgrades") if upgrades.empty?

        return PredicateResult.fail(reason: "upgrade_plan upgrade is missing deps") if upgrades.any? { |upgrade| Array(upgrade["deps"]).empty? }

        priorities = upgrades.filter_map { |upgrade| upgrade["priority"] }
        PredicateResult.pass(evidence: { artifact_id: artifact.id, upgrade_count: upgrades.count, highest_priority: priorities.min })
      end
    end
  end
end

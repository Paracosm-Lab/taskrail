module Engine
  module Predicates
    class AuditProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "dependency_audit").first
        return PredicateResult.fail(reason: "no dependency_audit artifact found") unless artifact

        dependencies = Array(artifact.data["dependencies"])
        return PredicateResult.fail(reason: "dependency_audit artifact has no outdated dependencies") if dependencies.empty?

        total_outdated = artifact.data["total_outdated"]
        if total_outdated && total_outdated != dependencies.count
          return PredicateResult.fail(reason: "dependency_audit total_outdated does not match dependencies")
        end

        cve_count = artifact.data.fetch("cve_count", dependencies.sum { |dependency| Array(dependency["cves"]).count })
        PredicateResult.pass(evidence: { artifact_id: artifact.id, dependencies_count: dependencies.count, cve_count: cve_count })
      end
    end
  end
end

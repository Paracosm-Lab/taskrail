module Engine
  module Predicates
    class ScanCompleted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "vulnerability_scan").first
        return PredicateResult.fail(reason: "no vulnerability_scan artifact found") unless artifact

        vulnerabilities = artifact.data.fetch("vulnerabilities", [])
        if vulnerabilities.empty?
          return PredicateResult.fail(reason: "vulnerability_scan artifact has no vulnerabilities")
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, vulnerability_count: vulnerabilities.count })
      end
    end
  end
end

module Engine
  module Predicates
    class JobInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "job_inventory").first
        return PredicateResult.fail(reason: "no job_inventory artifact found") unless artifact

        jobs = artifact.data["jobs"]
        return PredicateResult.fail(reason: "job_inventory artifact has no jobs") unless jobs.is_a?(Array) && jobs.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, jobs_count: jobs.count })
      end
    end
  end
end

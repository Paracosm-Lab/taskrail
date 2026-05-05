module Engine
  module Predicates
    class ObservabilityAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "observability_assessment").first
        return PredicateResult.fail(reason: "no observability_assessment artifact found") unless artifact

        assessed_jobs = artifact.data["jobs"]
        return PredicateResult.fail(reason: "observability_assessment artifact has no assessments") unless assessed_jobs.is_a?(Array) && assessed_jobs.any?

        inventory = @claim.work_item.artifacts.where(kind: "job_inventory").order(created_at: :desc).first
        inventory_jobs = Array(inventory&.data&.fetch("jobs", []))
        expected_names = inventory_jobs.filter_map { |job| job["class_name"] }
        assessed_names = assessed_jobs.filter_map { |job| job["class_name"] }
        missing_names = expected_names - assessed_names
        return PredicateResult.fail(reason: "observability_assessment missing jobs: #{missing_names.join(', ')}") if missing_names.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, assessed_jobs_count: assessed_jobs.count })
      end
    end
  end
end

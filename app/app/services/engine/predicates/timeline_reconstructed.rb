module Engine
  module Predicates
    class TimelineReconstructed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "incident_timeline").first
        return PredicateResult.fail(reason: "missing incident_timeline artifact") unless artifact

        phases = artifact.data["phases"]
        return PredicateResult.fail(reason: "incident_timeline artifact has no phases array") unless phases.is_a?(Array)

        total_duration = artifact.data["total_duration_minutes"]
        return PredicateResult.fail(reason: "incident_timeline artifact missing total_duration_minutes") unless total_duration

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            phase_count: phases.count,
            total_duration_minutes: total_duration
          }
        )
      end
    end
  end
end

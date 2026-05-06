module Engine
  module Predicates
    class ArtifactsIngested
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "incident_artifacts").first
        return PredicateResult.fail(reason: "missing incident_artifacts artifact") unless artifact

        sentry_events  = artifact.data["sentry_events"]
        slack_messages = artifact.data["slack_messages"]
        deploys        = artifact.data["deploys"]

        has_events = (sentry_events.is_a?(Array) && sentry_events.any?) ||
                     (slack_messages.is_a?(Array) && slack_messages.any?) ||
                     (deploys.is_a?(Array) && deploys.any?)

        return PredicateResult.fail(reason: "incident_artifacts artifact has no event sources (sentry_events, slack_messages, or deploys)") unless has_events

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            sentry_event_count: sentry_events.is_a?(Array) ? sentry_events.count : 0,
            slack_message_count: slack_messages.is_a?(Array) ? slack_messages.count : 0,
            deploy_count: deploys.is_a?(Array) ? deploys.count : 0
          }
        )
      end
    end
  end
end

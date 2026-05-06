module Engine
  module Predicates
    class UpdatesDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "incident_updates").first
        return PredicateResult.fail(reason: "missing incident_updates artifact") unless artifact

        runbook_updates = artifact.data["runbook_updates"]
        new_alerts      = artifact.data["new_alerts"]

        has_updates = (runbook_updates.is_a?(Array) && runbook_updates.any?) ||
                      (new_alerts.is_a?(Array) && new_alerts.any?)

        return PredicateResult.fail(reason: "incident_updates artifact has neither runbook_updates nor new_alerts") unless has_updates

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            runbook_update_count: runbook_updates.is_a?(Array) ? runbook_updates.count : 0,
            new_alert_count: new_alerts.is_a?(Array) ? new_alerts.count : 0
          }
        )
      end
    end
  end
end

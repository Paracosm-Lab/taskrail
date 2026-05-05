require "rails_helper"

RSpec.describe "Chaos cookbook predicates" do
  let(:queue) { WorkQueue.create!(name: "Chaos", slug: "chaos-predicate-#{SecureRandom.hex(4)}", stages: ["stage", "done"]) }
  let(:work_item) { WorkItem.create!(title: "Chaos exercise", spec_url: "inline", work_queue: queue, stage_name: "stage") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: "completed", started_at: Time.current) }

  def create_artifact(kind, data)
    Artifact.create!(work_item: work_item, claim: claim, kind: kind, data: data)
  end

  it "passes disruption_planned when scenario and reversal_steps are present" do
    artifact = create_artifact("disruption_plan", {
      "scenario" => "stop postgres in staging",
      "reversal_steps" => ["docker compose start postgres"]
    })

    result = Engine::Predicates::DisruptionPlanned.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails disruption_planned without reversal steps" do
    create_artifact("disruption_plan", { "scenario" => "stop postgres in staging" })

    result = Engine::Predicates::DisruptionPlanned.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("disruption_plan missing scenario or reversal_steps")
  end

  it "passes disruption_executed when commands_run is nonempty" do
    artifact = create_artifact("disruption_record", { "commands_run" => ["docker compose stop postgres"] })

    result = Engine::Predicates::DisruptionExecuted.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes impact_observed when an impact_report exists even with zero alerts" do
    artifact = create_artifact("impact_report", { "alerts_fired" => 0, "services_affected" => [] })

    result = Engine::Predicates::ImpactObserved.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes recovery_evaluated when scores are present" do
    artifact = create_artifact("recovery_evaluation", { "scores" => { "detection" => 4 } })

    result = Engine::Predicates::RecoveryEvaluated.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes alerts_detected when events are nonempty" do
    artifact = create_artifact("detected_alerts", { "events" => [{ "id" => "evt-1" }] })

    result = Engine::Predicates::AlertsDetected.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails alerts_detected when no events are present" do
    create_artifact("detected_alerts", { "events" => [] })

    result = Engine::Predicates::AlertsDetected.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("detected_alerts missing events")
  end

  it "passes diagnosis_produced when root_cause_hypothesis is present" do
    artifact = create_artifact("diagnosis", { "root_cause_hypothesis" => "postgres unavailable" })

    result = Engine::Predicates::DiagnosisProduced.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes runbook_selected when artifact exists even with null selection" do
    artifact = create_artifact("runbook_selection", { "selected_runbook" => nil, "gaps" => ["no matching runbook"] })

    result = Engine::Predicates::RunbookSelected.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes runbook_executed when steps_executed is present" do
    artifact = create_artifact("runbook_execution", { "steps_executed" => [], "overall_success" => false })

    result = Engine::Predicates::RunbookExecuted.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "passes recovery_verified only when service_healthy is true" do
    artifact = create_artifact("recovery_verification", { "service_healthy" => true, "verification_checks" => [] })

    result = Engine::Predicates::RecoveryVerified.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails recovery_verified when service_healthy is false" do
    create_artifact("recovery_verification", { "service_healthy" => false, "verification_checks" => [] })

    result = Engine::Predicates::RecoveryVerified.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("recovery_verification service_healthy is not true")
  end
end

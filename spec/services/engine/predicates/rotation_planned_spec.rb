require "rails_helper"

RSpec.describe Engine::Predicates::RotationPlanned do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Credential Rotation #{SecureRandom.hex(4)}", slug: "credential-rotation-plan-#{SecureRandom.hex(4)}", stages: ["draft_rotation_plan", "done"])
    queue.stage_configs.create!(stage_name: "draft_rotation_plan", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft rotation plan", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_rotation_plan")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with a rotation count when a rotation_plan artifact has rotations with steps" do
    claim = build_claim(artifacts: [{ kind: "rotation_plan", data: { "rotations" => [{ "credential_name" => "STRIPE_SECRET_KEY", "steps" => [{ "action" => "Generate replacement manually" }] }] } }])
    artifact = claim.artifacts.find_by!(kind: "rotation_plan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, rotations_count: 1 })
  end

  it "fails when no rotation_plan artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing rotation_plan artifact")
  end

  it "fails when the rotation_plan artifact has no rotations" do
    claim = build_claim(artifacts: [{ kind: "rotation_plan", data: { "rotations" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rotation_plan artifact has no rotations")
  end

  it "fails when any rotation is missing steps" do
    claim = build_claim(artifacts: [{ kind: "rotation_plan", data: { "rotations" => [{ "credential_name" => "STRIPE_SECRET_KEY", "steps" => [] }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rotation_plan rotations are missing steps")
  end
end

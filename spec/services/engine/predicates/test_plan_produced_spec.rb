require "rails_helper"

RSpec.describe Engine::Predicates::TestPlanProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Test Plan Queue", slug: "test-plan-#{SecureRandom.hex(4)}", stages: ["identify_gaps", "done"])
    queue.stage_configs.create!(stage_name: "identify_gaps", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "identify_gaps")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when test_plan artifact has non-empty units" do
    claim = build_claim(artifacts: [
      { kind: "test_plan", data: { "units" => [{ "file" => "app/models/widget.rb", "method" => "#valid?", "gap_type" => "model validation", "risk" => "high", "description" => "validates name" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "test_plan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when test_plan artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing test_plan artifact with units")
  end

  it "fails when units is empty" do
    claim = build_claim(artifacts: [{ kind: "test_plan", data: { "units" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing test_plan artifact with units")
  end
end

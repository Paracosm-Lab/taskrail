require "rails_helper"

RSpec.describe Engine::Predicates::AssessmentComplete do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Ops AssessmentComplete", slug: "ops-instrumentation-assessment-#{SecureRandom.hex(4)}", stages: ["assess", "done"])
    queue.stage_configs.create!(stage_name: "assess", adapter_type: "fake")
    item = WorkItem.create!(title: "Test", spec_url: "opaque spec", work_queue: queue, stage_name: "assess")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when instrumentation assessment artifact exists" do
    claim = build_claim(artifacts: [{ kind: "instrumentation_assessment", data: { "score" => 4 } }])
    artifact = claim.artifacts.find_by!(kind: "instrumentation_assessment")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no instrumentation assessment artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no instrumentation assessment artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "clusters", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no instrumentation assessment artifact found")
  end
end

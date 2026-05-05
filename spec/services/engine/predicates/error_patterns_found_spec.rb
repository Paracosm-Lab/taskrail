require "rails_helper"

RSpec.describe Engine::Predicates::ErrorPatternsFound do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Error Patterns Found",
      slug: "error-patterns-found-#{SecureRandom.hex(4)}",
      stages: ["scan", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "scan")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when an error_patterns artifact exists with findings" do
    claim = build_claim(artifacts: [
      { kind: "error_patterns", data: { "patterns" => [{ "file" => "app/controllers/payments_controller.rb" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "error_patterns")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, pattern_count: 1 })
  end

  it "passes when an error_patterns artifact exists with an empty patterns array" do
    claim = build_claim(artifacts: [
      { kind: "error_patterns", data: { "patterns" => [] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "error_patterns")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, pattern_count: 0 })
  end

  it "fails when no error_patterns artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no error_patterns artifact found")
  end
end

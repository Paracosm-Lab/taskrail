require "rails_helper"

RSpec.describe Engine::Predicates::StandardDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Standard #{SecureRandom.hex(4)}",
      slug: "standard-drafted-predicate-#{SecureRandom.hex(4)}",
      stages: ["draft_standard", "done"]
    )
    queue.stage_configs.create!(stage_name: "draft_standard", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft logging standard", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_standard")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a logging standard artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "logging_standard",
          data: {
            "standard" => {
              "format" => "structured_json",
              "required_fields_by_level" => { "error" => ["request_id", "operation", "error_class"] },
              "guidelines" => ["info for lifecycle events"],
              "examples" => [{ "scenario" => "job", "log" => { "event" => "job_started" } }],
              "anti_patterns" => ["puts params.inspect"]
            }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "logging_standard")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no logging standard artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging standard artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "logging_assessment", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging standard artifact found")
  end
end

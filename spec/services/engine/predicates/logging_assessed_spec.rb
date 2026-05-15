require "rails_helper"

RSpec.describe Engine::Predicates::LoggingAssessed do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Assessment #{SecureRandom.hex(4)}",
      slug: "logging-assessed-predicate-#{SecureRandom.hex(4)}",
      stages: ["assess_quality", "done"]
    )
    queue.stage_configs.create!(stage_name: "assess_quality", adapter_type: "fake")
    item = WorkItem.create!(title: "Assess logs", spec_url: "opaque spec", work_queue: queue, stage_name: "assess_quality")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a logging assessment artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "logging_assessment",
          data: {
            "best_patterns" => [{ "file" => "app/services/good_logger.rb", "reason" => "structured context" }],
            "worst_offenders" => [{ "file" => "app/controllers/orders_controller.rb", "reason" => "puts params.inspect" }],
            "scores_by_file" => { "app/controllers/orders_controller.rb" => 20 },
            "recommended_standard" => { "format" => "structured_json" }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "logging_assessment")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no logging assessment artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging assessment artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "log_inventory", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging assessment artifact found")
  end
end

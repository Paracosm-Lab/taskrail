require "rails_helper"

RSpec.describe Engine::Predicates::LogInventoryProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Audit #{SecureRandom.hex(4)}",
      slug: "logging-audit-predicate-#{SecureRandom.hex(4)}",
      stages: ["scan_log_statements", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan_log_statements", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit logs", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_log_statements")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a log inventory artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "log_inventory",
          data: {
            "statements" => [
              {
                "file" => "app/controllers/orders_controller.rb",
                "line" => 12,
                "logger" => "Rails.logger",
                "level" => "info",
                "format" => "unstructured",
                "content" => "processing order",
                "context_present" => false
              }
            ],
            "summary" => { "total" => 1, "by_format" => { "unstructured" => 1 }, "by_level" => { "info" => 1 }, "by_service" => {} }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "log_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no log inventory artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no log inventory artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "logging_assessment", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no log inventory artifact found")
  end
end

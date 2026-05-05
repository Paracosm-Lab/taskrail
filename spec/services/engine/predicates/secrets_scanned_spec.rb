require "rails_helper"

RSpec.describe Engine::Predicates::SecretsScanned do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Credential Rotation #{SecureRandom.hex(4)}",
      slug: "credential-rotation-predicate-#{SecureRandom.hex(4)}",
      stages: ["scan_secrets", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan_secrets", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit credentials", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_secrets")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with counts when a secret_inventory artifact has a secrets array" do
    claim = build_claim(
      artifacts: [
        {
          kind: "secret_inventory",
          data: {
            "secrets" => [
              {
                "name" => "STRIPE_SECRET_KEY",
                "type" => "payment_api_key",
                "locations" => [{ "file" => "config/payment.yml", "line" => 3, "how" => "hardcoded" }],
                "in_git_history" => true
              }
            ],
            "total_count" => 1,
            "hardcoded_count" => 1
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "secret_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, total_count: 1, hardcoded_count: 1 })
  end

  it "fails when no secret_inventory artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing secret_inventory artifact")
  end

  it "fails when the secret_inventory artifact does not contain a secrets array" do
    claim = build_claim(artifacts: [{ kind: "secret_inventory", data: { "summary" => "not structured" } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("secret_inventory artifact has no secrets array")
  end
end

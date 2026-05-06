require "rails_helper"

RSpec.describe Engine::Predicates::FlowsMapped do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Integration Tests #{SecureRandom.hex(4)}",
      slug: "integration-tests-flows-#{SecureRandom.hex(4)}",
      stages: %w[map_user_flows done]
    )
    queue.stage_configs.create!(stage_name: "map_user_flows", adapter_type: "fake")
    item = WorkItem.create!(title: "Map critical flows", spec_url: "opaque spec", work_queue: queue, stage_name: "map_user_flows")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed, started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when a user_flows artifact has at least one flow" do
    claim = build_claim(
      artifacts: [
        {
          kind: "user_flows",
          data: {
            "flows" => [
              {
                "name" => "Create work item and advance",
                "entry_point" => "POST /api/v1/work_items",
                "steps" => [
                  {
                    "action" => "create work item",
                    "service" => "Api::V1::WorkItemsController",
                    "endpoint_or_method" => "create",
                    "data_deps" => ["integration_tests queue"]
                  }
                ],
                "expected_outcome" => "work item advances after engine tick",
                "services_involved" => ["API", "Engine::Runner", "Adapters::FakeAdapter"]
              }
            ]
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "user_flows")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, flows_count: 1 })
  end

  it "fails when the user_flows artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no user_flows artifact found")
  end

  it "fails when flows is empty" do
    claim = build_claim(artifacts: [{ kind: "user_flows", data: { "flows" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("user_flows artifact has no flows")
  end

  it "fails when the flow has no steps" do
    claim = build_claim(
      artifacts: [
        {
          kind: "user_flows",
          data: { "flows" => [{ "name" => "Incomplete", "entry_point" => "POST /api/v1/work_items", "steps" => [] }] }
        }
      ]
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("user_flows artifact has flows without steps: Incomplete")
  end
end

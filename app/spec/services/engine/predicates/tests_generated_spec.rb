require "rails_helper"

RSpec.describe Engine::Predicates::TestsGenerated do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Tests Generated Queue", slug: "tests-generated-#{SecureRandom.hex(4)}", stages: ["generate_tests", "done"])
    queue.stage_configs.create!(stage_name: "generate_tests", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "generate_tests")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when generated_tests artifact has non-empty specs" do
    claim = build_claim(artifacts: [
      { kind: "generated_tests", data: { "specs" => [{ "path" => "spec/models/widget_spec.rb", "content" => "require \"rails_helper\"\n" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "generated_tests")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, artifact_kind: "generated_tests", specs_count: 1 })
  end

  it "passes when an integration_specs artifact has non-empty specs" do
    claim = build_claim(artifacts: [
      {
        kind: "integration_specs",
        data: {
          "specs" => [
            {
              "path" => "spec/requests/create_work_item_flow_spec.rb",
              "content" => "require \"rails_helper\"\n",
              "flow_name" => "Create work item and advance",
              "boundaries_tested" => ["API", "Engine"]
            }
          ]
        }
      }
    ])
    artifact = claim.artifacts.find_by!(kind: "integration_specs")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, artifact_kind: "integration_specs", specs_count: 1 })
  end

  it "fails when generated_tests artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing generated_tests or integration_specs artifact with specs")
  end

  it "fails when specs is empty" do
    claim = build_claim(artifacts: [{ kind: "generated_tests", data: { "specs" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing generated_tests or integration_specs artifact with specs")
  end
end

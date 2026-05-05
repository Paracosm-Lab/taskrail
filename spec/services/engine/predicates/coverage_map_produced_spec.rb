require "rails_helper"

RSpec.describe Engine::Predicates::CoverageMapProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Coverage Map Queue", slug: "coverage-map-#{SecureRandom.hex(4)}", stages: ["scan_coverage", "done"])
    queue.stage_configs.create!(stage_name: "scan_coverage", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_coverage")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when coverage_map artifact has non-empty files" do
    claim = build_claim(artifacts: [
      { kind: "coverage_map", data: { "files" => [{ "path" => "app/models/widget.rb", "coverage_pct" => 42.0, "uncovered_lines" => ["8-14"] }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "coverage_map")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when coverage_map artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_map artifact with files")
  end

  it "fails when files is empty" do
    claim = build_claim(artifacts: [{ kind: "coverage_map", data: { "files" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_map artifact with files")
  end
end

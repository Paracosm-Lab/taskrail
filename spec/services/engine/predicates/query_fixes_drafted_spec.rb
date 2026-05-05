require "rails_helper"

RSpec.describe Engine::Predicates::QueryFixesDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Fixes #{SecureRandom.hex(4)}", slug: "query-fixes-#{SecureRandom.hex(4)}", stages: ["draft_fixes", "done"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_fixes")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_patches artifact has a migration" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [{ "filename" => "db/migrate/add_index.rb" }], "code_patches" => [] } }])
    artifact = claim.artifacts.find_by!(kind: "query_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, migration_count: 1, code_patch_count: 0 })
  end

  it "passes when query_patches artifact has a code patch" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [], "code_patches" => [{ "file" => "app/controllers/posts_controller.rb" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, migration_count: 0, code_patch_count: 1 })
  end

  it "fails when query_patches artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_patches artifact found")
  end

  it "fails when query_patches has no migrations or code patches" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [], "code_patches" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_patches artifact has no migrations or code patches")
  end
end

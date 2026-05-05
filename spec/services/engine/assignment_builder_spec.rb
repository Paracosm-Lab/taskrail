require "rails_helper"

RSpec.describe Engine::AssignmentBuilder do
  it "builds a complete assignment package" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    stage_config = StageConfig.create!(
      work_queue: queue,
      stage_name: "intake",
      allowed_skills: ["read_spec"],
      forbidden_skills: ["deploy"],
      completion_criteria: ["report_present"],
      timeout_seconds: 600,
      model_override: "fake-model",
      agent_prompt: "Classify this",
      adapter_type: "fake"
    )
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Classify thing",
      stage_name: "intake",
      spec_url: "opaque-spec",
      tags: { "risk" => "low" },
      metadata: { "feedback" => "try again", "human_answer" => "use bearer tokens" }
    )
    upstream_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    upstream_report = Report.create!(claim: upstream_claim, work_item: work_item, stage_name: "previous", status: :success, body: { "summary" => "upstream" })
    upstream_artifact = Artifact.create!(claim: upstream_claim, work_item: work_item, kind: "branch", data: { "name" => "sc/upstream" })
    claim = Claim.create!(work_item: work_item, agent_type: "fake", timeout_seconds: 600)

    assignment = described_class.new(claim: claim, stage_config: stage_config).build

    expect(assignment[:claim_id]).to eq(claim.id)
    expect(assignment[:callback_url]).to include("/api/v1/claims/#{claim.id}/report")
    expect(assignment[:work_item]).to include(id: work_item.id, title: "Classify thing", spec_url: "opaque-spec", tags: { "risk" => "low" }, parent_id: nil)
    expect(assignment[:stage]).to include(name: "intake", allowed_skills: ["read_spec"], forbidden_skills: ["deploy"], completion_criteria: ["report_present"])
    expect(assignment[:prompt]).to eq("Classify this")
    expect(assignment[:model]).to eq("fake-model")
    expect(assignment[:context][:spec_content]).to eq("opaque-spec")
    expect(assignment[:context][:upstream_reports]).to include(upstream_report.body)
    expect(assignment[:context][:upstream_artifacts]).to include({ "kind" => upstream_artifact.kind, "data" => upstream_artifact.data })
    expect(assignment[:context][:feedback]).to eq("try again")
    expect(assignment[:context][:human_answer]).to eq("use bearer tokens")
    expect(assignment[:limits][:timeout_seconds]).to eq(600)
  end
end

require "rails_helper"

RSpec.describe "dead code removal workflow integration" do
  it "advances through artifact-backed cookbook stages" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "dead_code_removal")
    work_item = WorkItem.create!(
      title: "Remove fixture dead code",
      spec_url: "./cookbooks/fixtures/apps/dead_code_app/README.md",
      work_queue: queue,
      stage_name: "scan_references"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "removal_candidates",
      data: {
        "dependencies" => [{ "name" => "unused_charting_gem", "path" => "Gemfile" }],
        "files" => [{ "path" => "app/models/unused_legacy_model.rb" }],
        "methods" => [{ "name" => "Customer#stale_score", "path" => "app/models/customer.rb" }],
        "routes" => [{ "name" => "reports#export", "path" => "config/routes.rb" }],
        "other" => []
      }
    )

    expect(Engine::Predicates::CandidatesIdentified.new(claim: scan_claim).call).to be_passed

    verify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: verify_claim,
      work_item: work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          { "type" => "method", "name" => "Customer#stale_score", "path" => "app/models/customer.rb", "classification" => "safe_to_remove", "reasoning" => "No inbound or dynamic references." },
          { "type" => "method", "name" => "Customer#active?", "path" => "app/models/customer.rb", "classification" => "needs_investigation", "reasoning" => "Referenced through public_send." }
        ]
      }
    )

    verify_result = Engine::Predicates::RemovalsVerified.new(claim: verify_claim).call
    expect(verify_result).to be_passed
    expect(verify_result.evidence[:safe_to_remove_count]).to eq(1)

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: draft_claim,
      work_item: work_item,
      kind: "removal_patches",
      data: {
        "patches" => [
          { "action" => "modify", "path" => "app/models/customer.rb", "description" => "Remove Customer#stale_score only." }
        ]
      }
    )

    expect(Engine::Predicates::RemovalsDrafted.new(claim: draft_claim).call).to be_passed
  end
end

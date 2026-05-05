require "rails_helper"
require "json"

RSpec.describe "dependency upgrade cookbook" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/dependency_upgrade") }

  it "ships a deterministic fixture app and audit script" do
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("Gemfile.lock")).to exist
    expect(fixture_root.join("package.json")).to exist
    expect(fixture_root.join("bin/dependency-audit")).to exist

    audit = JSON.parse(`ruby #{fixture_root.join("bin/dependency-audit")}`)

    expect(audit.fetch("dependencies").map { |dep| dep.fetch("name") }).to include("rack", "puma", "lodash")
    expect(audit.fetch("total_outdated")).to eq(audit.fetch("dependencies").count)
    expect(audit.fetch("cve_count")).to be >= 1
  end

  it "loads the dependency_upgrade queue and validates each cookbook artifact" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "dependency_upgrade")
    work_item = WorkItem.create!(work_queue: queue, title: "Upgrade stale deps", spec_url: "fixture", stage_name: "audit_dependencies")

    audit_claim = Claim.create!(work_item: work_item, agent_type: "shell_script", status: "completed", started_at: Time.current)
    audit_data = JSON.parse(`ruby #{fixture_root.join("bin/dependency-audit")}`)
    Artifact.create!(work_item: work_item, claim: audit_claim, kind: "dependency_audit", data: audit_data)
    expect(Engine::PredicateRegistry.resolve("audit_produced").new(claim: audit_claim).call).to be_passed

    plan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: plan_claim,
      kind: "upgrade_plan",
      data: {
        "upgrades" => [
          { "deps" => ["rack"], "priority" => 1, "risk" => "medium", "reason" => "CVE fix" },
          { "deps" => ["puma"], "priority" => 2, "risk" => "low", "reason" => "patch" }
        ],
        "spawn_work_items" => []
      }
    )
    expect(Engine::PredicateRegistry.resolve("upgrade_plan_produced").new(claim: plan_claim).call).to be_passed

    upgrade_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: upgrade_claim,
      kind: "upgrade_patches",
      data: {
        "dep_name" => "rack",
        "from_version" => "2.2.8",
        "to_version" => "3.0.9",
        "branch_name" => "dependency-upgrade/rack-3-0-9",
        "patches" => [
          { "file" => "Gemfile", "original" => "gem \"rack\", \"2.2.8\"", "replacement" => "gem \"rack\", \"3.0.9\"" }
        ]
      }
    )
    expect(Engine::PredicateRegistry.resolve("upgrade_drafted").new(claim: upgrade_claim).call).to be_passed
  end

  it "keeps dependency upgrade queue paths portable" do
    queue_yaml = Rails.root.join("config/queues/dependency_upgrade.yml").read

    expect(queue_yaml).not_to include(Rails.root.to_s)
    expect(queue_yaml).not_to include(["", "Users", ""].join("/"))
    expect(queue_yaml).to include("cookbooks/fixtures/apps/dependency_upgrade")
    expect(queue_yaml).to include("file://prompts/deps_audit.md")
  end
end

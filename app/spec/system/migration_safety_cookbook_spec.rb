require "rails_helper"

RSpec.describe "migration safety cookbook fixture" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/migration_safety_app") }

  it "contains an unsafe and safe migration scenario for large-table NOT NULL defaults" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/models/order.rb")).to exist
    expect(fixture_root.join("app/services/order_backfill.rb")).to exist
    expect(fixture_root.join("db/migrate/20240101000000_add_region_to_orders_unsafe.rb")).to exist
    expect(fixture_root.join("db/migrate/20240101000001_add_region_to_orders_safe.rb")).to exist
    expect(fixture_root.join("scripts/run_rollback_test.rb")).to exist

    unsafe_migration = fixture_root.join("db/migrate/20240101000000_add_region_to_orders_unsafe.rb").read
    expect(unsafe_migration).to include("null: false")
    expect(unsafe_migration).to include("default:")

    safe_migration = fixture_root.join("db/migrate/20240101000001_add_region_to_orders_safe.rb").read
    expect(safe_migration).to include("add_column :orders, :region")
    expect(safe_migration).to include("OrderBackfill")
    expect(safe_migration).to include("change_column_null")
  end

  it "defines the artifact contract for migration safety stages" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "migration_safety")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Check orders region migration",
      spec_url: "cookbooks/fixtures/apps/migration_safety_app/README.md",
      stage_name: "scan_impact"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "impact_map",
      data: {
        "affected_files" => ["app/models/order.rb", "app/services/order_backfill.rb", "db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
        "affected_tests" => ["spec/system/migration_safety_cookbook_spec.rb"],
        "affected_configs" => [],
        "external_consumers" => ["warehouse export"]
      }
    )
    expect(Engine::PredicateRegistry.resolve("impact_mapped").new(claim: scan_claim).call).to be_passed

    risk_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: risk_claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "risks" => [
          { "category" => "downtime", "description" => "NOT NULL default can lock orders", "severity" => "blocking", "affected_paths" => ["db/migrate/20240101000000_add_region_to_orders_unsafe.rb"], "mitigation" => "expand/backfill/contract" }
        ],
        "blocking_risks" => ["NOT NULL default can lock orders"]
      }
    )
    expect(Engine::PredicateRegistry.resolve("risks_enumerated").new(claim: risk_claim).call).to be_passed

    rollback_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: rollback_claim,
      work_item: work_item,
      kind: "rollback_plan",
      data: {
        "procedures" => [
          {
            "risk_ref" => "NOT NULL default can lock orders",
            "steps" => [{ "action" => "rollback migration", "command" => "bin/rails db:rollback STEP=1", "verification" => "orders.region removed" }],
            "estimated_time" => "5 minutes",
            "data_loss_potential" => "none"
          }
        ]
      }
    )
    expect(Engine::PredicateRegistry.resolve("rollback_drafted").new(claim: rollback_claim).call).to be_passed

    test_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: test_claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => true,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => []
      }
    )
    expect(Engine::PredicateRegistry.resolve("rollback_tested").new(claim: test_claim).call).to be_passed
  end

  it "has a deterministic rollback runner that reports green JSON" do
    output = IO.popen(["ruby", fixture_root.join("scripts/run_rollback_test.rb").to_s], &:read)
    data = JSON.parse(output)

    expect(data).to include(
      "migration_succeeded" => true,
      "rollback_succeeded" => true,
      "data_intact" => true,
      "health_checks_passed" => true,
      "issues" => []
    )
  end

  it "documents the cookbook source spec and verification workflow" do
    doc = Rails.root.join("docs/cookbooks/migration-safety.md")

    expect(doc).to exist
    content = doc.read
    expect(content).to include("docs/specs/cookbook-14-migration-safety.md")
    expect(content).to include("migration_safety")
    expect(content).to include("impact_map")
    expect(content).to include("rollback_test_results")
    expect(content).to include("cookbooks/fixtures/apps/migration_safety_app")
  end
end

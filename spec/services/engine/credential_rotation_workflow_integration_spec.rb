require "rails_helper"

RSpec.describe "credential rotation workflow integration" do
  it "advances through read-only artifact-backed credential stages" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "credential_rotation")
    work_item = WorkItem.create!(
      title: "Audit leaky credential fixture",
      spec_url: "test/fixtures/apps/leaky_credentials/README.md",
      work_queue: queue,
      stage_name: "scan_secrets"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "secret_inventory",
      data: {
        "secrets" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "type" => "payment_api_key",
            "locations" => [
              { "file" => "test/fixtures/apps/leaky_credentials/config/payment.yml", "line" => 2, "how" => "hardcoded" },
              { "file" => "test/fixtures/apps/leaky_credentials/app/services/billing_reconciler.rb", "line" => 3, "how" => "env_var" }
            ],
            "in_git_history" => true
          }
        ],
        "total_count" => 1,
        "hardcoded_count" => 1
      }
    )
    expect(Engine::Predicates::SecretsScanned.new(claim: scan_claim).call).to be_passed

    dependency_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: dependency_claim,
      work_item: work_item,
      kind: "dependency_map",
      data: {
        "credentials" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "type" => "payment_api_key",
            "scope" => "payment admin",
            "services" => [
              { "name" => "web", "reads_at" => "startup", "fallback" => false },
              { "name" => "billing-worker", "reads_at" => "startup", "fallback" => false }
            ],
            "shared_across" => 2,
            "rotation_requires_restart" => true
          }
        ]
      }
    )
    expect(Engine::Predicates::DependenciesMapped.new(claim: dependency_claim).call).to be_passed

    risk_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: risk_claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "credentials" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "exposure_risk" => "hardcoded and in git history",
            "blast_radius" => "payment provider admin",
            "estimated_age_days" => 540,
            "sharing_risk" => "shared across web and billing-worker",
            "overall_risk" => "critical",
            "rationale" => "Rotate immediately after moving to a secrets manager."
          }
        ],
        "critical_count" => 1,
        "summary" => "One critical credential requires coordinated rotation."
      }
    )
    risk_result = Engine::Predicates::RiskAssessed.new(claim: risk_claim).call
    expect(risk_result).to be_passed
    expect(risk_result.evidence[:critical_count]).to eq(1)

    plan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: plan_claim,
      work_item: work_item,
      kind: "rotation_plan",
      data: {
        "rotations" => [
          {
            "credential_name" => "STRIPE_SECRET_KEY",
            "risk_level" => "critical",
            "steps" => [
              {
                "action" => "Generate replacement Stripe key manually",
                "target" => "Stripe dashboard",
                "verification" => "New key exists but old key remains active",
                "rollback" => "Keep old key active"
              },
              {
                "action" => "Update STRIPE_SECRET_KEY in the secrets manager and restart web then billing-worker",
                "target" => "web,billing-worker",
                "verification" => "Payment and nightly billing health checks pass",
                "rollback" => "Restore old secret value and restart services"
              }
            ],
            "services_affected" => ["web", "billing-worker"],
            "estimated_downtime" => "low with rolling restart",
            "requires_code_change" => true,
            "code_change_description" => "Move config/payment.yml hardcoded value to ENV.fetch before rotating."
          }
        ],
        "rotation_order" => ["STRIPE_SECRET_KEY"]
      }
    )
    plan_result = Engine::Predicates::RotationPlanned.new(claim: plan_claim).call
    expect(plan_result).to be_passed
    expect(plan_result.evidence[:rotations_count]).to eq(1)
  end
end

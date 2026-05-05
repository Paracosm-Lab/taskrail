require "rails_helper"

RSpec.describe "job observability cookbook fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/uninstrumented_jobs") }

  it "contains representative background jobs for observability scoring" do
    expect(fixture_root.join("app/jobs/export_job.rb")).to exist
    expect(fixture_root.join("app/jobs/billing_job.rb")).to exist
    expect(fixture_root.join("app/jobs/sync_job.rb")).to exist
    expect(fixture_root.join("app/jobs/cleanup_job.rb")).to exist

    expect(fixture_root.join("app/jobs/export_job.rb").read).to include("class ExportJob < ApplicationJob")
    expect(fixture_root.join("app/jobs/billing_job.rb").read).to include("sidekiq_options retry: 5, queue: :critical, deadline: 300")
    expect(fixture_root.join("app/jobs/sync_job.rb").read).to include("sidekiq_options retry: true")
    expect(fixture_root.join("app/jobs/cleanup_job.rb").read).to include("rescue => e")
  end

  it "defines the artifact contract for the background job observability stages" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "job_observability")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Audit fixture jobs",
      spec_url: "test/fixtures/apps/uninstrumented_jobs",
      stage_name: "scan_job_classes"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "job_inventory",
      data: {
        "framework" => "active_job",
        "jobs" => [
          { "class_name" => "ExportJob", "file" => "app/jobs/export_job.rb", "queue" => "default", "args" => ["user_id"] },
          { "class_name" => "BillingJob", "file" => "app/jobs/billing_job.rb", "queue" => "critical", "args" => ["invoice_id"] },
          { "class_name" => "SyncJob", "file" => "app/jobs/sync_job.rb", "queue" => "default", "args" => ["record_id"] },
          { "class_name" => "CleanupJob", "file" => "app/jobs/cleanup_job.rb", "queue" => "default", "args" => [] }
        ]
      }
    )

    expect(Engine::PredicateRegistry.resolve("job_inventory_produced").new(claim: scan_claim).call).to be_passed

    assess_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: assess_claim,
      work_item: work_item,
      kind: "observability_assessment",
      data: {
        "jobs" => [
          { "class_name" => "ExportJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["no instrumentation"] },
          { "class_name" => "BillingJob", "scores" => {}, "total_score" => 2.0, "classification" => "well_instrumented", "critical_gaps" => [] },
          { "class_name" => "SyncJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["infinite retries"] },
          { "class_name" => "CleanupJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["swallows errors"] }
        ],
        "summary" => { "total_jobs" => 4, "well_instrumented" => 1, "under_instrumented" => 0, "blind" => 3, "worst_job" => "ExportJob" }
      }
    )

    result = Engine::PredicateRegistry.resolve("observability_assessed").new(claim: assess_claim).call

    expect(result).to be_passed
    expect(result.evidence[:assessed_jobs_count]).to eq(4)
  end
end

require "rails_helper"

RSpec.describe Engine::Predicates::ObservabilityAssessed do
  def build_claim
    queue = WorkQueue.create!(name: "Job Observability #{SecureRandom.hex(4)}", slug: "job-observability-#{SecureRandom.hex(4)}", stages: %w[scan_job_classes assess_observability done])
    work_item = WorkItem.create!(work_queue: queue, title: "Audit jobs", spec_url: "local", stage_name: "assess_observability")
    Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
  end

  let(:claim) { build_claim }

  before do
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "job_inventory",
      data: {
        "framework" => "active_job",
        "jobs" => [
          { "class_name" => "ExportJob", "file" => "app/jobs/export_job.rb" },
          { "class_name" => "BillingJob", "file" => "app/jobs/billing_job.rb" }
        ]
      }
    )
  end

  it "passes with evidence when every inventoried job has an assessment" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "observability_assessment",
      data: {
        "jobs" => [
          { "class_name" => "ExportJob", "scores" => { "error_capture" => 0 }, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["no logging"] },
          { "class_name" => "BillingJob", "scores" => { "error_capture" => 3 }, "total_score" => 2.1, "classification" => "well_instrumented", "critical_gaps" => [] }
        ],
        "summary" => { "total_jobs" => 2, "well_instrumented" => 1, "under_instrumented" => 0, "blind" => 1, "worst_job" => "ExportJob" }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, assessed_jobs_count: 2 })
  end

  it "fails when the assessment artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no observability_assessment artifact found")
  end

  it "fails when the assessment has no job entries" do
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "observability_assessment", data: { "jobs" => [], "summary" => { "total_jobs" => 0 } })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("observability_assessment artifact has no assessments")
  end

  it "fails when any inventoried job is missing from the assessment" do
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "observability_assessment",
      data: {
        "jobs" => [{ "class_name" => "ExportJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => [] }],
        "summary" => { "total_jobs" => 1 }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("observability_assessment missing jobs: BillingJob")
  end
end

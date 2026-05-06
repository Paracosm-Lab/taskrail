require "rails_helper"

RSpec.describe Engine::Predicates::JobInventoryProduced do
  def build_claim
    queue = WorkQueue.create!(name: "Job Observability #{SecureRandom.hex(4)}", slug: "job-observability-#{SecureRandom.hex(4)}", stages: %w[scan_job_classes done])
    work_item = WorkItem.create!(work_queue: queue, title: "Audit jobs", spec_url: "local", stage_name: "scan_job_classes")
    Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
  end

  it "passes with evidence when a job_inventory artifact has at least one job" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "job_inventory",
      data: {
        "framework" => "active_job",
        "jobs" => [
          {
            "class_name" => "ExportJob",
            "file" => "app/jobs/export_job.rb",
            "queue" => "default",
            "args" => ["user_id"]
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, jobs_count: 1 })
  end

  it "fails when the job_inventory artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no job_inventory artifact found")
  end

  it "fails when the job_inventory artifact has no jobs" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "job_inventory", data: { "framework" => "active_job", "jobs" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("job_inventory artifact has no jobs")
  end
end

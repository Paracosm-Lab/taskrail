require "rails_helper"

RSpec.describe Engine::Predicates::CoverageChecked do
  def build_claim
    queue = WorkQueue.create!(name: "PR Review #{SecureRandom.hex(4)}", slug: "pr-review-cov-#{SecureRandom.hex(4)}", stages: %w[coverage_check architectural_review])
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/3", work_queue: queue, stage_name: "coverage_check")
    Claim.create!(work_item: work_item, agent_type: "shell_script", status: :active)
  end

  it "passes when coverage_report has changed file coverage data" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "coverage_report",
      data: {
        "overall_delta" => 0.0,
        "changed_files" => [{ "file" => "app/controllers/orders_controller.rb", "coverage_pct" => 92.5, "uncovered_lines" => [42] }],
        "new_files_without_tests" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, changed_files_count: 1, new_files_without_tests_count: 0)
  end

  it "fails when coverage_report is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_report artifact")
  end

  it "fails when changed_files is not an array" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "coverage_report", data: { "overall_delta" => 0.0, "changed_files" => nil })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("coverage_report changed_files must be an array")
  end
end

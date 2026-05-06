require "rails_helper"

RSpec.describe Engine::Predicates::ChecksPassed do
  def build_claim
    queue = WorkQueue.create!(
      name: "PR Review #{SecureRandom.hex(4)}",
      slug: "pr-review-#{SecureRandom.hex(4)}",
      stages: %w[run_checks security_scan]
    )
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/1", work_queue: queue, stage_name: "run_checks")
    Claim.create!(work_item: work_item, agent_type: "shell_script", status: :active)
  end

  it "passes with evidence when lint, tests, and build all pass" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "check_results",
      data: {
        "lint" => { "passed" => true, "errors" => [] },
        "tests" => { "passed" => true, "failures" => [] },
        "build" => { "passed" => true, "errors" => [] }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, checks: %w[lint tests build])
  end

  it "fails when check_results is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing check_results artifact")
  end

  it "fails with the failing check name when any check did not pass" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "check_results",
      data: {
        "lint" => { "passed" => true, "errors" => [] },
        "tests" => { "passed" => false, "failures" => [{ "file" => "spec/models/order_spec.rb", "message" => "expected true" }] },
        "build" => { "passed" => true, "errors" => [] }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("PR checks failed: tests")
  end
end

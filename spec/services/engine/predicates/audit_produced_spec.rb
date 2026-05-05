require "rails_helper"

RSpec.describe Engine::Predicates::AuditProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-#{SecureRandom.hex(4)}",
      stages: ["audit_dependencies", "done"]
    )
    queue.stage_configs.create!(stage_name: "audit_dependencies", adapter_type: "fake")
    item = WorkItem.create!(title: "Upgrade dependencies", spec_url: "local", work_queue: queue, stage_name: "audit_dependencies")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when dependency_audit lists outdated dependencies" do
    claim = build_claim(artifacts: [{
      kind: "dependency_audit",
      data: {
        "dependencies" => [
          { "name" => "rack", "current" => "2.2.8", "latest" => "3.0.9", "type" => "major", "cves" => ["CVE-2024-1234"], "changelog_url" => "https://example.test/rack" },
          { "name" => "puma", "current" => "6.4.0", "latest" => "6.4.2", "type" => "patch", "cves" => [], "changelog_url" => "https://example.test/puma" }
        ],
        "total_outdated" => 2,
        "cve_count" => 1
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "dependency_audit")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, dependencies_count: 2, cve_count: 1 })
  end

  it "fails when the dependency_audit artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no dependency_audit artifact found")
  end

  it "fails when dependency_audit has no dependencies" do
    claim = build_claim(artifacts: [{ kind: "dependency_audit", data: { "dependencies" => [], "total_outdated" => 0, "cve_count" => 0 } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("dependency_audit artifact has no outdated dependencies")
  end

  it "fails when total_outdated does not match the dependency list" do
    claim = build_claim(artifacts: [{
      kind: "dependency_audit",
      data: { "dependencies" => [{ "name" => "rack" }], "total_outdated" => 2, "cve_count" => 0 }
    }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("dependency_audit total_outdated does not match dependencies")
  end
end

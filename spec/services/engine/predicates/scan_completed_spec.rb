require "rails_helper"

RSpec.describe Engine::Predicates::ScanCompleted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Security Scan",
      slug: "security-scan-#{SecureRandom.hex(4)}",
      stages: %w[scan_vulnerabilities done]
    )
    queue.stage_configs.create!(stage_name: "scan_vulnerabilities", adapter_type: "fake")
    item = WorkItem.create!(title: "Scan repo", spec_url: "local", work_queue: queue, stage_name: "scan_vulnerabilities")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when vulnerability_scan has vulnerabilities" do
    claim = build_claim(artifacts: [
      {
        kind: "vulnerability_scan",
        data: {
          "vulnerabilities" => [
            {
              "category" => "injection",
              "file" => "app/controllers/orders_controller.rb",
              "line" => 12,
              "evidence" => 'Order.where("id = #{params[:id]}")',
              "exploitability" => "easy",
              "severity" => "critical"
            }
          ]
        }
      }
    ])
    artifact = claim.artifacts.find_by!(kind: "vulnerability_scan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, vulnerability_count: 1 })
  end

  it "fails when vulnerability_scan is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no vulnerability_scan artifact found")
  end

  it "fails when vulnerability_scan has no vulnerabilities" do
    claim = build_claim(artifacts: [
      { kind: "vulnerability_scan", data: { "vulnerabilities" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("vulnerability_scan artifact has no vulnerabilities")
  end
end

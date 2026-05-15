require "rails_helper"

RSpec.describe CodexCliPoller do
  it "passes the external id as the final command argument" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", "puts({ status: 'running', received: ARGV.last }.to_json)"],
      external_id: "codex-run-1",
      working_directory: Rails.root.to_s
    ).call

    expect(result.status).to eq("running")
    expect(result.metadata["received"]).to eq("codex-run-1")
    expect(result.exit_status).to eq(0)
    expect(result.duration_ms).to be >= 0
  end

  it "returns succeeded JSON metadata with stdout" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", "puts({ status: 'succeeded', stdout: 'done', report: { summary: 'ok' }, artifacts: [{ kind: 'branch', data: { name: 'sc/build' } }] }.to_json)"],
      external_id: "codex-run-1",
      working_directory: Rails.root.to_s
    ).call

    expect(result.status).to eq("succeeded")
    expect(result.stdout).to eq("done")
    expect(result.metadata.dig("report", "summary")).to eq("ok")
    expect(result.metadata.dig("artifacts", 0, "data", "name")).to eq("sc/build")
  end

  it "returns failed JSON metadata with stderr and exit status" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", "puts({ status: 'failed', stderr: 'boom', exit_status: 12 }.to_json)"],
      external_id: "codex-run-1",
      working_directory: Rails.root.to_s
    ).call

    expect(result.status).to eq("failed")
    expect(result.stderr).to eq("boom")
    expect(result.exit_status).to eq(12)
  end

  it "returns failed result for non-zero poll command without raising" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "warn ARGV.last; exit 9"],
      external_id: "codex-run-1",
      working_directory: Rails.root.to_s
    ).call

    expect(result.status).to eq("failed")
    expect(result.stderr).to include("codex-run-1")
    expect(result.exit_status).to eq(9)
  end

  it "terminates commands that exceed the timeout" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "sleep 2; puts 'late'"],
      external_id: "codex-run-1",
      working_directory: Rails.root.to_s,
      timeout_seconds: 0.1
    ).call

    expect(result.status).to eq("failed")
    expect(result.stdout).not_to include("late")
    expect(result.stderr).to include("timed out")
    expect(result.exit_status).to eq(124)
  end
end

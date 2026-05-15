require "rails_helper"

RSpec.describe CodexCliSubmitter do
  it "passes the prompt to the configured command and captures output" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "prompt = STDIN.read; puts prompt.upcase"],
      prompt: "build this",
      working_directory: Rails.root.to_s
    ).call

    expect(result.stdout).to include("BUILD THIS")
    expect(result.stderr).to eq("")
    expect(result.exit_status).to eq(0)
    expect(result.duration_ms).to be >= 0
  end

  it "parses the external id from JSON stdout" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", "STDIN.read; puts({ id: 'codex-run-1', branch: 'sc-1' }.to_json)"],
      prompt: "build this",
      working_directory: Rails.root.to_s,
      timeout_seconds: 1
    ).call

    expect(result.external_id).to eq("codex-run-1")
    expect(result.metadata["branch"]).to eq("sc-1")
  end

  it "captures non-zero exits without raising" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "warn STDIN.read; exit 9"],
      prompt: "bad",
      working_directory: Rails.root.to_s
    ).call

    expect(result.stderr).to include("bad")
    expect(result.exit_status).to eq(9)
  end

  it "terminates commands that exceed the timeout" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "sleep 2; puts 'late'"],
      prompt: "",
      working_directory: Rails.root.to_s,
      timeout_seconds: 0.1
    ).call

    expect(result.stdout).not_to include("late")
    expect(result.stderr).to include("timed out")
    expect(result.exit_status).to eq(124)
  end
end

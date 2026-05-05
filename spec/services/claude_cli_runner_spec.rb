require "rails_helper"

RSpec.describe ClaudeCliRunner do
  it "passes the prompt to the configured command and captures output" do
    result = described_class.new(
      command: "ruby",
      args: ["-e", "prompt = STDIN.read; puts prompt.upcase"],
      prompt: "hello",
      working_directory: Rails.root.to_s
    ).call

    expect(result.stdout).to include("HELLO")
    expect(result.stderr).to eq("")
    expect(result.exit_status).to eq(0)
    expect(result.duration_ms).to be >= 0
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

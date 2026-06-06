require "rails_helper"

RSpec.describe KiloCliSubmitter do
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

  it "parses JSON stdout into metadata" do
    result = described_class.new(
      command: "ruby",
      args: ["-rjson", "-e", 'STDIN.read; puts({ "result" => "ok", "message" => "done" }.to_json)'],
      prompt: "build this",
      working_directory: Rails.root.to_s,
      timeout_seconds: 1
    ).call

    expect(result.metadata["result"]).to eq("ok")
    expect(result.metadata["message"]).to eq("done")
  end

  it "handles JSON event stream output (JSON-lines)" do
    result = described_class.new(
      command: "ruby",
      args: [
        "-rjson",
        "-e",
        <<~'RUBY'
          STDIN.read
          puts({ "type" => "step_start", "sessionID" => "ses_abc123" }.to_json)
          puts({ "type" => "text", "part" => { "text" => "all done" } }.to_json)
          puts({ "type" => "step_finish", "part" => { "reason" => "stop", "cost" => 0, "tokens" => { "total" => 100 } } }.to_json)
        RUBY
      ],
      prompt: "build this",
      working_directory: Rails.root.to_s
    ).call

    expect(result.exit_status).to eq(0)
    expect(result.metadata).to include(
      "mode" => "json_lines",
      "session_id" => "ses_abc123",
      "final_message" => "all done",
      "cost" => 0
    )
    expect(result.external_id).to eq("ses_abc123")
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

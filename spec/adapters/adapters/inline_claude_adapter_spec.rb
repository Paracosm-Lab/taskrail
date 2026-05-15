require "rails_helper"

RSpec.describe Adapters::InlineClaudeAdapter do
  it "returns success with report, artifact, and trace event when Claude exits zero" do
    runner_result = ClaudeCliRunner::Result.new(stdout: "Summary from Claude", stderr: "", exit_status: 0, duration_ms: 12)
    runner = instance_double(ClaudeCliRunner, call: runner_result)
    allow(ClaudeCliRunner).to receive(:new).and_return(runner)

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.report["response"]).to include("Summary from Claude")
    expect(result.artifacts.first["kind"]).to eq("agent_report")
    expect(result.artifacts.first["data"]["content"]).to include("Summary from Claude")
    expect(result.trace_events.first["event_type"]).to eq("claude_cli")
  end

  it "returns failure when Claude exits non-zero" do
    runner_result = ClaudeCliRunner::Result.new(stdout: "", stderr: "boom", exit_status: 2, duration_ms: 12)
    runner = instance_double(ClaudeCliRunner, call: runner_result)
    allow(ClaudeCliRunner).to receive(:new).and_return(runner)

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("failed")
    expect(result.report["exit_status"]).to eq(2)
  end

  it "records trace timing and token cost fields" do
    runner_result = ClaudeCliRunner::Result.new(stdout: "ok", stderr: "", exit_status: 0, duration_ms: 25)
    allow(ClaudeCliRunner).to receive(:new).and_return(instance_double(ClaudeCliRunner, call: runner_result))

    event = described_class.new.execute(assignment).trace_events.first

    expect(event).to include("duration_ms" => 25, "tokens_in" => 0, "tokens_out" => 0, "cost_cents" => 0)
  end

  def assignment
    {
      claim_id: 1,
      work_item: { id: 1, title: "Classify feature", spec_url: "opaque" },
      stage: {
        name: "intake",
        adapter_config: {
          "command" => "claude",
          "args" => ["--print"],
          "working_directory" => Rails.root.to_s,
          "output_artifact_kind" => "agent_report"
        },
        allowed_skills: ["read_spec"],
        forbidden_skills: [],
        completion_criteria: ["report_present"]
      },
      prompt: "Classify this work item.",
      model: "claude-test",
      context: { spec_content: "Do it" },
      limits: { timeout_seconds: 600 }
    }
  end
end

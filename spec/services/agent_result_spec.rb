require "rails_helper"

RSpec.describe AgentResult do
  it "normalizes success results" do
    result = described_class.success(
      report: { "summary" => "done" },
      artifacts: [{ "kind" => "branch", "data" => { "name" => "sc/test" } }],
      trace_events: [{ "event_type" => "decision", "output_summary" => "created branch" }]
    )

    expect(result.status).to eq("success")
    expect(result.report).to eq("summary" => "done")
    expect(result.artifacts.first["kind"]).to eq("branch")
    expect(result.trace_events.first["event_type"]).to eq("decision")
  end

  it "normalizes failure results" do
    result = described_class.failure(report: { "summary" => "nope" })

    expect(result.status).to eq("failure")
    expect(result.report).to eq("summary" => "nope")
    expect(result.artifacts).to eq([])
    expect(result.trace_events).to eq([])
  end

  it "normalizes blocked results with a question" do
    result = described_class.blocked(question: "Which auth method?", report: { "reason" => "ambiguous" })

    expect(result.status).to eq("blocked")
    expect(result.blocked_question).to eq("Which auth method?")
    expect(result.report).to eq("reason" => "ambiguous")
  end
end

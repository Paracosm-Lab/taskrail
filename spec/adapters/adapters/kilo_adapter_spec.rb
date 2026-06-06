require "rails_helper"

RSpec.describe Adapters::KiloAdapter do
  it "returns success when Kilo exits zero with valid output" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done", "artifacts": []}',
      stderr: "",
      exit_status: 0,
      duration_ms: 500,
      external_id: nil,
      metadata: { "message" => "done", "artifacts" => [] }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result).to be_a(AgentResult)
    expect(result.status).to eq("success")
    expect(result.report["summary"]).to include("Kilo completed")
    expect(result.trace_events.first["event_type"]).to eq("kilo_run")
  end

  it "extracts branch artifacts from structured output in final message" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "",
      exit_status: 0,
      duration_ms: 500,
      external_id: nil,
      metadata: {
        "final_message" => <<~TEXT
          Fixed the issue.

          ```json
          {
            "artifacts": [
              { "kind": "branch", "data": { "name": "postrunner/fix-lint" } }
            ]
          }
          ```
        TEXT
      }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.artifacts).to include("kind" => "branch", "data" => { "name" => "postrunner/fix-lint" })
  end

  it "extracts branch artifacts directly from metadata artifacts array" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "",
      exit_status: 0,
      duration_ms: 500,
      external_id: nil,
      metadata: {
        "artifacts" => [{ "kind" => "branch", "data" => { "name" => "postrunner/from-metadata" } }]
      }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.artifacts).to include("kind" => "branch", "data" => { "name" => "postrunner/from-metadata" })
  end

  it "returns failure when Kilo exits non-zero" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "kilo: model not found",
      exit_status: 1,
      duration_ms: 100,
      external_id: nil,
      metadata: {}
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("failed")
    expect(result.report["stderr"]).to eq("kilo: model not found")
    expect(result.report["exit_status"]).to eq(1)
  end

  it "returns timeout when Kilo exits with 124" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: "",
      stderr: "command timed out after 300 seconds",
      exit_status: 124,
      duration_ms: 300_000,
      external_id: nil,
      metadata: {}
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("timeout")
    expect(result.report["summary"]).to include("timed out")
  end

  it "passes model and --dir from adapter_config to the submitter" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 100,
      external_id: nil,
      metadata: { "message" => "done" }
    )

    expect(KiloCliSubmitter).to receive(:new).with(
      hash_including(args: include("--model", "deepseek/deepseek-chat", "--dir"))
    ).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    described_class.new.execute(assignment)
  end

  it "constructs trace events with kilo_run event type" do
    submitter_result = KiloCliSubmitter::Result.new(
      stdout: '{"message": "done"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 250,
      external_id: nil,
      metadata: { "message" => "done" }
    )
    allow(KiloCliSubmitter).to receive(:new).and_return(instance_double(KiloCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    trace = result.trace_events.first
    expect(trace["event_type"]).to eq("kilo_run")
    expect(trace["duration_ms"]).to eq(250)
    expect(trace["metadata"]["command"]).to eq("kilo")
  end

  def assignment
    {
      claim_id: 1,
      work_item: { id: 1, title: "Fix lint issue", spec_url: "opaque", metadata: {} },
      stage: {
        name: "fix",
        adapter_config: {
          "command" => "kilo",
          "args" => ["run", "--auto", "--format", "json"],
          "model" => "deepseek/deepseek-chat",
          "output_artifact_kind" => "branch",
          "branch_prefix" => "postrunner/"
        },
        allowed_skills: [],
        forbidden_skills: [],
        completion_criteria: ["branch_created"]
      },
      prompt: "Fix this lint finding.",
      context: { spec_content: "Fix it" },
      limits: { timeout_seconds: 300 }
    }
  end
end

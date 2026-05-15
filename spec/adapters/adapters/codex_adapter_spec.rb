require "rails_helper"

RSpec.describe Adapters::CodexAdapter do
  it "returns an async result when Codex submission succeeds" do
    submitter_result = CodexCliSubmitter::Result.new(
      stdout: '{"id":"codex-run-1","branch":"taskrail/build-1"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 14,
      external_id: "codex-run-1",
      metadata: { "id" => "codex-run-1", "branch" => "taskrail/build-1" }
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result).to be_a(Engine::AsyncAdapterResult)
    expect(result.provider).to eq("codex")
    expect(result.external_id).to eq("codex-run-1")
    expect(result.status).to eq("submitted")
    expect(result.metadata["branch"]).to eq("taskrail/build-1")
    expect(result.metadata["exit_status"]).to eq(0)
    expect(result.trace_events.first["event_type"]).to eq("codex_submit")
  end

  it "keeps external reference metadata for async claim creation" do
    submitter_result = CodexCliSubmitter::Result.new(
      stdout: '{"id":"codex-run-2"}',
      stderr: "",
      exit_status: 0,
      duration_ms: 8,
      external_id: "codex-run-2",
      metadata: { "id" => "codex-run-2" }
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("submitted")
    expect(result.external_id).to eq("codex-run-2")
    expect(result.metadata).to include("exit_status" => 0, "output_artifact_kind" => "branch")
  end

  it "returns failure when Codex submission exits non-zero" do
    submitter_result = CodexCliSubmitter::Result.new(
      stdout: "",
      stderr: "boom",
      exit_status: 2,
      duration_ms: 14,
      external_id: nil,
      metadata: {}
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("failed")
    expect(result.report["exit_status"]).to eq(2)
    expect(result.trace_events.first["event_type"]).to eq("codex_submit")
  end

  it "returns failure when Codex submission omits an external id" do
    submitter_result = CodexCliSubmitter::Result.new(
      stdout: '{}',
      stderr: "",
      exit_status: 0,
      duration_ms: 14,
      external_id: nil,
      metadata: {}
    )
    allow(CodexCliSubmitter).to receive(:new).and_return(instance_double(CodexCliSubmitter, call: submitter_result))

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["summary"]).to include("missing external id")
  end

  def assignment
    {
      claim_id: 1,
      work_item: { id: 1, title: "Build feature", spec_url: "opaque", metadata: {} },
      stage: {
        name: "build",
        adapter_config: {
          "command" => "codex",
          "args" => ["exec", "--json"],
          "working_directory" => Rails.root.to_s,
          "branch_prefix" => "taskrail",
          "output_artifact_kind" => "branch"
        },
        allowed_skills: ["test-driven-development"],
        forbidden_skills: ["deploy"],
        completion_criteria: ["branch_created"]
      },
      prompt: "Build this work item.",
      model: "codex-test",
      context: { spec_content: "Do it" },
      limits: { timeout_seconds: 600 }
    }
  end
end

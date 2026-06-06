# spec/adapters/adapters/github_ci_poll_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubCiPollAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "await_ci",
        adapter_type: "github_ci_poll",
        adapter_config: { "poll_interval_seconds" => 30, "timeout_seconds" => 900 }
      },
      work_item: {
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "pull_request", "data" => { "number" => 42, "url" => "https://github.com/MyScribbl/crm-service/pull/42" } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns AsyncAdapterResult with submitted status" do
      result = adapter.execute(assignment)

      expect(result).to be_a(Engine::AsyncAdapterResult)
      expect(result.provider).to eq("github_ci_poll")
      expect(result.status).to eq("submitted")
      expect(result.external_id).to eq("MyScribbl/crm-service#42")
    end
  end

  describe "#check_status" do
    let(:claim) do
      instance_double(Claim,
        assignment: { "async" => { "metadata" => { "repository" => "MyScribbl/crm-service", "pr_number" => 42 } } },
        metadata: {}
      )
    end

    it "returns :running when checks are pending" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"headRefOid":"abc123"}',
          stderr: "", exit_status: 0, duration_ms: 100
        ),
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"workflow_runs":[{"name":"test","status":"in_progress","conclusion":null}]}',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      expect(adapter.check_status(claim)).to eq(:running)
    end

    it "returns success AgentResult when all checks pass" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"headRefOid":"abc123"}',
          stderr: "", exit_status: 0, duration_ms: 100
        ),
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"workflow_runs":[{"name":"test","status":"completed","conclusion":"success"}]}',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      result = adapter.check_status(claim)
      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("success")
    end

    it "returns failure AgentResult when a check fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"headRefOid":"abc123"}',
          stderr: "", exit_status: 0, duration_ms: 100
        ),
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: '{"workflow_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}',
          stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      result = adapter.check_status(claim)
      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("failure")
    end
  end
end

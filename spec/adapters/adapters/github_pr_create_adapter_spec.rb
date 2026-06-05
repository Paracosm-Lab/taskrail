# spec/adapters/adapters/github_pr_create_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubPrCreateAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "open_pr",
        adapter_type: "github_pr_create",
        adapter_config: { "base_branch" => "main", "title_template" => "fix: {work_item_title}" }
      },
      work_item: {
        title: "shellcheck SC2086 in bin/deploy.sh",
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "branch", "data" => { "branch" => "postrunner/sc2086-deploy-sh" } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns success with pull_request artifact when gh succeeds" do
      pr_url = "https://github.com/MyScribbl/crm-service/pull/99"
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: pr_url, stderr: "", exit_status: 0, duration_ms: 200
        )
      )

      result = adapter.execute(assignment)

      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("success")
      pr_artifact = result.artifacts.find { |a| a["kind"] == "pull_request" }
      expect(pr_artifact).to be_present
      expect(pr_artifact["data"]["url"]).to eq(pr_url)
    end

    it "returns failure when gh command fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "", stderr: "error creating PR", exit_status: 1, duration_ms: 100
        )
      )

      result = adapter.execute(assignment)

      expect(result).to be_a(AgentResult)
      expect(result.status).to eq("failure")
      expect(result.report["stderr"]).to include("error creating PR")
    end

    it "extracts branch from upstream branch artifact" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "https://github.com/test/repo/pull/1", stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      adapter.execute(assignment)

      expect(adapter).to have_received(:run_command) do |cmd|
        expect(cmd).to include("--head")
        head_idx = cmd.index("--head")
        expect(cmd[head_idx + 1]).to eq("postrunner/sc2086-deploy-sh")
      end
    end
  end
end

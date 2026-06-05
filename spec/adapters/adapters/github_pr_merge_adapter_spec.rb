# spec/adapters/adapters/github_pr_merge_adapter_spec.rb
require "rails_helper"

RSpec.describe Adapters::GithubPrMergeAdapter do
  let(:adapter) { described_class.new }

  let(:assignment) do
    {
      stage: {
        name: "merge",
        adapter_type: "github_pr_merge",
        adapter_config: { "strategy" => "squash", "delete_branch" => true }
      },
      work_item: {
        tags: { "repository" => "MyScribbl/crm-service" }
      },
      context: {
        upstream_artifacts: [
          { "kind" => "pull_request", "data" => { "number" => 42 } }
        ]
      }
    }
  end

  describe "#execute" do
    it "returns success when merge succeeds" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "Merged", stderr: "", exit_status: 0, duration_ms: 200
        )
      )

      result = adapter.execute(assignment)

      expect(result.status).to eq("success")
      merge_artifact = result.artifacts.find { |a| a["kind"] == "merge_result" }
      expect(merge_artifact["data"]["merged"]).to be true
      expect(merge_artifact["data"]["strategy"]).to eq("squash")
    end

    it "passes --squash and --delete-branch flags" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "Merged", stderr: "", exit_status: 0, duration_ms: 100
        )
      )

      adapter.execute(assignment)

      expect(adapter).to have_received(:run_command) do |cmd|
        expect(cmd).to include("--squash")
        expect(cmd).to include("--delete-branch")
      end
    end

    it "returns failure when merge fails" do
      allow(adapter).to receive(:run_command).and_return(
        Adapters::Concerns::GithubCli::CommandResult.new(
          stdout: "", stderr: "merge conflict", exit_status: 1, duration_ms: 100
        )
      )

      result = adapter.execute(assignment)
      expect(result.status).to eq("failure")
    end
  end
end

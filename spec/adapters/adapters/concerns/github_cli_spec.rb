# spec/adapters/adapters/concerns/github_cli_spec.rb
require "rails_helper"
require "ostruct"

RSpec.describe Adapters::Concerns::GithubCli do
  let(:test_class) do
    Class.new(Adapters::BaseAdapter) do
      include Adapters::Concerns::GithubCli
      # Expose private methods for testing
      public :run_command, :extract_pr_artifact, :build_trace
    end
  end
  let(:adapter) { test_class.new }

  describe "#run_command" do
    it "captures stdout and exit status from a successful command" do
      result = adapter.run_command(["echo", "hello"])
      expect(result.stdout).to eq("hello")
      expect(result.exit_status).to eq(0)
      expect(result.success?).to be true
    end

    it "captures stderr and non-zero exit from a failed command" do
      result = adapter.run_command(["sh", "-c", "echo err >&2; exit 1"])
      expect(result.stderr).to include("err")
      expect(result.exit_status).to eq(1)
      expect(result.success?).to be false
    end
  end

  describe "#extract_pr_artifact" do
    it "extracts pull_request artifact data from upstream artifacts" do
      assignment = {
        "context" => {
          "upstream_artifacts" => [
            { "kind" => "pull_request", "data" => { "number" => 42, "url" => "https://github.com/test/repo/pull/42" } }
          ]
        }
      }
      expect(adapter.extract_pr_artifact(assignment)).to eq({ "number" => 42, "url" => "https://github.com/test/repo/pull/42" })
    end

    it "returns empty hash when no pull_request artifact exists" do
      assignment = { "context" => { "upstream_artifacts" => [] } }
      expect(adapter.extract_pr_artifact(assignment)).to eq({})
    end
  end

  describe "#build_trace" do
    it "returns a trace event hash" do
      result = OpenStruct.new(stdout: "ok", exit_status: 0, duration_ms: 150)
      trace = adapter.build_trace(["gh", "pr", "create"], result, 150)
      expect(trace["event_type"]).to eq("github_cli")
      expect(trace["metadata"]["exit_status"]).to eq(0)
      expect(trace["duration_ms"]).to eq(150)
    end
  end
end

require "open3"

module Adapters
  module Concerns
    module GithubCli
      CommandResult = Data.define(:stdout, :stderr, :exit_status, :duration_ms) do
        def success?
          exit_status.zero?
        end
      end

      private

      def run_command(cmd, working_directory: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        opts = {}
        opts[:chdir] = working_directory if working_directory
        stdout, stderr, status = Open3.capture3(*cmd, **opts)
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = ((finished - started) * 1000).round

        CommandResult.new(
          stdout: stdout.strip,
          stderr: stderr.strip,
          exit_status: status.exitstatus,
          duration_ms: duration_ms
        )
      end

      def extract_pr_artifact(assignment)
        artifacts = assignment.dig("context", "upstream_artifacts") || []
        pr = artifacts.find { |a| a["kind"] == "pull_request" }
        pr&.fetch("data", {}) || {}
      end

      def build_trace(cmd, result, duration_ms = nil)
        {
          "event_type" => "github_cli",
          "input_summary" => cmd.join(" ").truncate(500),
          "output_summary" => result.stdout.to_s.truncate(500),
          "duration_ms" => duration_ms || result.try(:duration_ms) || 0,
          "tokens_in" => 0,
          "tokens_out" => 0,
          "cost_cents" => 0,
          "metadata" => { "exit_status" => result.exit_status, "command" => cmd.join(" ") }
        }
      end
    end
  end
end

module Adapters
  class GithubPrMergeAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      pr_data = extract_pr_artifact(assignment)
      repository = assignment.dig("work_item", "tags", "repository")
      config = assignment.dig("stage", "adapter_config") || {}
      strategy = config.fetch("strategy", "squash")
      delete_branch = config.fetch("delete_branch", true)
      pr_number = pr_data["number"].to_s

      cmd = ["gh", "pr", "merge", pr_number, "--repo", repository, "--#{strategy}"]
      cmd += ["--delete-branch"] if delete_branch

      result = run_command(cmd)

      if result.success?
        AgentResult.success(
          report: { "summary" => "Merged PR ##{pr_number} via #{strategy}" },
          artifacts: [{ "kind" => "merge_result", "data" => { "pr_number" => pr_data["number"], "strategy" => strategy, "merged" => true } }],
          trace_events: [build_trace(cmd, result)]
        )
      else
        AgentResult.failure(
          report: { "summary" => "Failed to merge PR ##{pr_number}", "stderr" => result.stderr, "exit_status" => result.exit_status },
          artifacts: [],
          trace_events: [build_trace(cmd, result)]
        )
      end
    end
  end
end

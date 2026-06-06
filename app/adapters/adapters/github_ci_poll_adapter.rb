module Adapters
  class GithubCiPollAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      pr_data = extract_pr_artifact(assignment)
      repository = assignment.dig("work_item", "tags", "repository")

      Engine::AsyncAdapterResult.new(
        provider: "github_ci_poll",
        external_id: "#{repository}##{pr_data['number']}",
        status: "submitted",
        metadata: {
          "repository" => repository,
          "pr_number" => pr_data["number"]
        },
        trace_events: []
      )
    end

    def check_status(claim)
      meta = claim.assignment.dig("async", "metadata") || claim.metadata || {}
      repo = meta["repository"]
      pr = meta["pr_number"]

      # Get the PR's head SHA
      sha_result = run_command(["gh", "pr", "view", pr.to_s, "--repo", repo, "--json", "headRefOid"])
      head_sha = (JSON.parse(sha_result.stdout) rescue {})["headRefOid"]
      return :running unless head_sha.present?

      # Query workflow runs for this SHA via the REST API (works with Actions read PAT permission)
      runs_result = run_command(["gh", "api", "repos/#{repo}/actions/runs?head_sha=#{head_sha}"])
      runs = (JSON.parse(runs_result.stdout) rescue {}).fetch("workflow_runs", [])

      return :running if runs.empty?

      pending = runs.any? { |r| r["status"] != "completed" }
      return :running if pending

      failed = runs.select { |r| r["conclusion"] == "failure" }
      if failed.any?
        AgentResult.failure(
          report: { "summary" => "CI failed: #{failed.map { |r| r['name'] }.join(', ')}", "runs" => runs },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "failure", "runs" => runs, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "api", "actions/runs"], runs_result)]
        )
      else
        AgentResult.success(
          report: { "summary" => "CI passed: #{runs.size} workflow runs green", "runs" => runs },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "success", "runs" => runs, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "api", "actions/runs"], runs_result)]
        )
      end
    end
  end
end

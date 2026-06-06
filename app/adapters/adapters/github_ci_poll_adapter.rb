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

      result = run_command(["gh", "pr", "checks", pr.to_s, "--repo", repo, "--json", "name,state,bucket"])
      checks = JSON.parse(result.stdout) rescue []

      return :running if checks.empty?
      pending = checks.any? { |c| !%w[SUCCESS FAILURE SKIPPED].include?(c["state"]) }
      return :running if pending

      failed = checks.select { |c| c["bucket"] == "fail" }
      if failed.any?
        AgentResult.failure(
          report: { "summary" => "CI failed: #{failed.map { |c| c['name'] }.join(', ')}", "checks" => checks },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "failure", "checks" => checks, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "pr", "checks"], result)]
        )
      else
        AgentResult.success(
          report: { "summary" => "CI passed: #{checks.size} checks green", "checks" => checks },
          artifacts: [{ "kind" => "ci_result", "data" => { "status" => "success", "checks" => checks, "pr_number" => pr } }],
          trace_events: [build_trace(["gh", "pr", "checks"], result)]
        )
      end
    end
  end
end

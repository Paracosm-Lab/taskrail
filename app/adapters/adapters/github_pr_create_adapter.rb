module Adapters
  class GithubPrCreateAdapter < BaseAdapter
    include Concerns::GithubCli

    def execute(assignment)
      assignment = assignment.deep_stringify_keys
      config = assignment.dig("stage", "adapter_config") || {}
      tags = assignment.dig("work_item", "tags") || {}
      repository = tags["repository"]
      branch = extract_branch(assignment)
      base = config.fetch("base_branch", "main")
      title = build_title(config, assignment)
      body = build_body(assignment)

      cmd = ["gh", "pr", "create", "--repo", repository, "--head", branch, "--base", base, "--title", title, "--body", body]

      result = run_command(cmd)

      if result.success?
        pr_data = parse_pr_url(result.stdout, repository, branch, base)
        AgentResult.success(
          report: { "summary" => "Created PR ##{pr_data['number']}", "url" => pr_data["url"] },
          artifacts: [{ "kind" => "pull_request", "data" => pr_data }],
          trace_events: [build_trace(cmd, result)]
        )
      else
        AgentResult.failure(
          report: { "summary" => "Failed to create PR", "stderr" => result.stderr, "exit_status" => result.exit_status },
          artifacts: [],
          trace_events: [build_trace(cmd, result)]
        )
      end
    end

    private

    def extract_branch(assignment)
      artifacts = assignment.dig("context", "upstream_artifacts") || []
      branch_artifact = artifacts.find { |a| a["kind"] == "branch" }
      branch_artifact&.dig("data", "branch") || "unknown-branch"
    end

    def build_title(config, assignment)
      template = config.fetch("title_template", "{work_item_title}")
      title = assignment.dig("work_item", "title") || "fix"
      template.gsub("{work_item_title}", title)
    end

    def build_body(assignment)
      reports = assignment.dig("context", "upstream_reports") || []
      latest = reports.last
      latest&.fetch("summary", "") || ""
    end

    def parse_pr_url(stdout, repository, branch, base)
      url = stdout.strip
      number = url.split("/").last.to_i
      { "number" => number, "url" => url, "branch" => branch, "base_branch" => base }
    end
  end
end

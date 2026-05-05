module Adapters
  class InlineClaudeAdapter < BaseAdapter
    DEFAULT_COMMAND = "claude"
    DEFAULT_ARGS = ["--print"].freeze
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    DEFAULT_ARTIFACT_KIND = "agent_report"
    OUTPUT_SUMMARY_LIMIT = 500

    def execute(assignment)
      normalized_assignment = assignment.deep_stringify_keys
      stage = normalized_assignment.fetch("stage")
      config = stage.fetch("adapter_config", {})
      command = config.fetch("command", DEFAULT_COMMAND)
      prompt = ClaudeAssignmentPrompt.new(normalized_assignment).to_s

      runner_result = ClaudeCliRunner.new(
        command: command,
        args: config.fetch("args", DEFAULT_ARGS),
        prompt: prompt,
        working_directory: config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY),
        timeout_seconds: normalized_assignment.dig("limits", "timeout_seconds")
      ).call

      trace_events = [trace_event(prompt, runner_result, command)]

      if runner_result.exit_status.zero?
        AgentResult.success(
          report: success_report(normalized_assignment, runner_result),
          artifacts: [success_artifact(normalized_assignment, runner_result, config)],
          trace_events: trace_events
        )
      else
        AgentResult.failure(
          report: failure_report(runner_result),
          artifacts: [],
          trace_events: trace_events
        )
      end
    end

    private

    def success_report(assignment, runner_result)
      {
        "summary" => "Claude completed #{assignment.dig('stage', 'name')}",
        "response" => runner_result.stdout,
        "stage" => assignment.dig("stage", "name")
      }
    end

    def failure_report(runner_result)
      {
        "summary" => "Claude command failed",
        "stdout" => runner_result.stdout,
        "stderr" => runner_result.stderr,
        "exit_status" => runner_result.exit_status
      }
    end

    def success_artifact(assignment, runner_result, config)
      {
        "kind" => config.fetch("output_artifact_kind", DEFAULT_ARTIFACT_KIND),
        "data" => {
          "content" => runner_result.stdout,
          "model" => assignment["model"],
          "stage" => assignment.dig("stage", "name")
        }
      }
    end

    def trace_event(prompt, runner_result, command)
      output = [runner_result.stdout, runner_result.stderr].reject(&:blank?).join("\n")
      {
        "event_type" => "claude_cli",
        "input_summary" => prompt.truncate(OUTPUT_SUMMARY_LIMIT),
        "output_summary" => output.truncate(OUTPUT_SUMMARY_LIMIT),
        "duration_ms" => runner_result.duration_ms,
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0,
        "metadata" => { "exit_status" => runner_result.exit_status, "command" => command }
      }
    end
  end
end

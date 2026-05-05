module Adapters
  class ShellScriptAdapter < BaseAdapter
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    OUTPUT_SUMMARY_LIMIT = 500

    def execute(assignment)
      stage = assignment.fetch(:stage)
      config = stage.fetch(:adapter_config, {})
      commands = config.fetch("commands", [])

      return missing_commands_result if commands.empty?

      working_directory = config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY)
      command_results = commands.map do |command_config|
        run_command(command_config, working_directory, assignment)
      end

      all_passed = command_results.all? { |result| result.fetch("exit_status").zero? }
      build_result(command_results, all_passed)
    end

    private

    def run_command(command_config, working_directory, assignment)
      command_result = ShellCommandRunner.new(
        command: command_config.fetch("command"),
        working_directory: working_directory,
        timeout_seconds: assignment.dig(:limits, :timeout_seconds)
      ).call

      {
        "name" => command_config.fetch("name"),
        "command" => command_config.fetch("command"),
        "stdout" => command_result.stdout,
        "stderr" => command_result.stderr,
        "exit_status" => command_result.exit_status,
        "duration_ms" => command_result.duration_ms
      }
    end

    def build_result(command_results, all_passed)
      report = {
        "summary" => "ran #{command_results.count} #{'command'.pluralize(command_results.count)}",
        "commands" => command_results.map { |result| report_command(result) },
        "failed_commands" => command_results.reject { |result| result.fetch("exit_status").zero? }.map { |result| result.fetch("name") }
      }
      artifacts = [{ "kind" => "test_results", "data" => { "passed" => all_passed, "commands" => report.fetch("commands") } }]
      trace_events = command_results.map { |result| trace_event(result) }

      if all_passed
        AgentResult.success(report: report, artifacts: artifacts, trace_events: trace_events)
      else
        AgentResult.failure(report: report, artifacts: artifacts, trace_events: trace_events)
      end
    end

    def missing_commands_result
      AgentResult.failure(
        report: { "summary" => "no shell commands configured", "failed_commands" => [] },
        artifacts: [{ "kind" => "test_results", "data" => { "passed" => false, "commands" => [] } }],
        trace_events: []
      )
    end

    def report_command(result)
      {
        "name" => result.fetch("name"),
        "exit_status" => result.fetch("exit_status"),
        "stdout" => result.fetch("stdout"),
        "stderr" => result.fetch("stderr"),
        "duration_ms" => result.fetch("duration_ms")
      }
    end

    def trace_event(result)
      {
        "event_type" => "shell_command",
        "input_summary" => "#{result.fetch('name')}: #{result.fetch('command')}",
        "output_summary" => summarize_output(result),
        "duration_ms" => result.fetch("duration_ms"),
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0,
        "metadata" => { "exit_status" => result.fetch("exit_status") }
      }
    end

    def summarize_output(result)
      output = [result.fetch("stdout"), result.fetch("stderr")].reject(&:blank?).join("\n")
      output.truncate(OUTPUT_SUMMARY_LIMIT)
    end
  end
end

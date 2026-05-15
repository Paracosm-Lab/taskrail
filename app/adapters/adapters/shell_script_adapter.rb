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
      validate_working_directory!(working_directory) if config.key?("working_directory")
      command_results = commands.map do |command_config|
        run_command(command_config, working_directory, assignment)
      end

      all_passed = command_results.all? { |result| result.fetch("exit_status").zero? }
      build_result(command_results, all_passed)
    end

    private

    def validate_working_directory!(dir)
      root = File.realpath(ENV.fetch("TASKRAIL_WORKSPACE_ROOT", "/tmp/taskrail-workspaces"))
      resolved = File.realpath(dir)
      return if resolved == root || resolved.start_with?("#{root}/")

      raise SecurityError, "working_directory #{dir} escapes sandbox root #{root}"
    end

    def run_command(command_config, working_directory, assignment)
      command_result = ShellCommandRunner.new(
        command: command_config.fetch("command"),
        working_directory: working_directory,
        timeout_seconds: assignment.dig(:limits, :timeout_seconds)
      ).call

      {
        "name" => command_config.fetch("name"),
        "command" => command_config.fetch("command"),
        "artifact" => command_config["artifact"],
        "previous_coverage" => command_config["previous_coverage"],
        "current_coverage" => command_config["current_coverage"],
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
      artifacts = validation_artifacts(command_results, all_passed, report.fetch("commands"))
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

    def validation_artifacts(command_results, all_passed, report_commands)
      mapped_artifacts = command_results.filter_map { |result| validation_artifact(result) }
      unmapped_commands = command_results.select { |result| result["artifact"].blank? }

      if mapped_artifacts.empty?
        return [{ "kind" => "test_results", "data" => { "passed" => all_passed, "commands" => report_commands } }]
      end

      if unmapped_commands.any?
        mapped_artifacts.unshift(
          "kind" => "test_results",
          "data" => {
            "passed" => unmapped_commands.all? { |result| result.fetch("exit_status").zero? },
            "commands" => unmapped_commands.map { |result| report_command(result) }
          }
        )
      end

      mapped_artifacts
    end

    def validation_artifact(result)
      case result["artifact"]
      when "test_results"
        { "kind" => "test_results", "data" => { "passed" => result.fetch("exit_status").zero?, "command" => report_command(result) } }
      when "lint"
        { "kind" => "lint", "data" => { "clean" => result.fetch("exit_status").zero?, "command" => report_command(result) } }
      when "coverage"
        {
          "kind" => "coverage",
          "data" => {
            "current" => result.fetch("current_coverage"),
            "previous" => result.fetch("previous_coverage"),
            "command" => report_command(result)
          }
        }
      end
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
        "input_summary" => "#{result.fetch('name')}: #{TraceRedactor.safe_summary(result.fetch('command'))}",
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

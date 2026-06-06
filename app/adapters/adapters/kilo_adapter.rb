module Adapters
  class KiloAdapter < BaseAdapter
    DEFAULT_COMMAND = "kilo"
    DEFAULT_ARGS = ["run", "--auto", "--format", "json"].freeze
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    OUTPUT_SUMMARY_LIMIT = 500

    def execute(assignment)
      normalized = assignment.deep_stringify_keys
      stage = normalized.fetch("stage")
      config = stage.fetch("adapter_config", {})
      command = config.fetch("command", DEFAULT_COMMAND)
      # Reuse CodexAssignmentPrompt — prompt format is adapter-agnostic
      prompt = CodexAssignmentPrompt.new(normalized).to_s

      args = config.fetch("args", DEFAULT_ARGS).dup
      model = config["model"]
      args.push("--model", model) if model.present?
      agent = config["agent"]
      args.push("--agent", agent) if agent.present?
      working_dir = config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY)
      args.push("--dir", working_dir)

      submitter_result = KiloCliSubmitter.new(
        command: command,
        args: args,
        prompt: prompt,
        working_directory: working_dir,
        timeout_seconds: normalized.dig("limits", "timeout_seconds")
      ).call

      trace_events = [trace_event(prompt, submitter_result, command)]

      if submitter_result.exit_status == KiloCliSubmitter::TIMEOUT_EXIT_STATUS
        AgentResult.timeout(
          report: timeout_report(submitter_result),
          artifacts: [],
          trace_events: trace_events
        )
      elsif submitter_result.exit_status.zero?
        AgentResult.success(
          report: success_report(normalized, submitter_result),
          artifacts: extract_artifacts(submitter_result),
          trace_events: trace_events
        )
      else
        AgentResult.failure(
          report: failure_report(submitter_result),
          artifacts: [],
          trace_events: trace_events
        )
      end
    rescue Errno::ENOENT
      AgentResult.failure(
        report: { "error" => "kilo command not found — is @kilocode/cli installed?" },
        artifacts: [],
        trace_events: []
      )
    end

    private

    def success_report(assignment, submitter_result)
      final_message = submitter_result.metadata["final_message"].presence || submitter_result.stdout
      {
        "summary" => "Kilo completed #{assignment.dig('stage', 'name')}",
        "response" => final_message,
        "stage" => assignment.dig("stage", "name")
      }.merge(structured_fields(final_message))
    end

    def extract_artifacts(submitter_result)
      configured_artifacts = submitter_result.metadata.fetch("artifacts", [])
      return configured_artifacts if configured_artifacts.is_a?(Array) && configured_artifacts.any?

      final_message = submitter_result.metadata["final_message"].presence || submitter_result.stdout
      structured_artifacts = structured_fields(final_message)["artifacts"]
      return structured_artifacts if structured_artifacts.is_a?(Array) && structured_artifacts.any?

      branch_name = submitter_result.metadata["branch"] || submitter_result.metadata.dig("artifact", "branch")
      return [] if branch_name.blank?

      [{ "kind" => "branch", "data" => { "name" => branch_name } }]
    end

    def structured_fields(message)
      ResponseParser.extract_structured_fields(message)
    end

    def failure_report(submitter_result)
      {
        "summary" => "Kilo submission failed",
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "exit_status" => submitter_result.exit_status
      }
    end

    def timeout_report(submitter_result)
      {
        "summary" => "Kilo submission timed out",
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "exit_status" => submitter_result.exit_status
      }
    end

    def trace_event(prompt, submitter_result, command)
      output = [submitter_result.stdout, submitter_result.stderr].reject(&:blank?).join("\n")
      {
        "event_type" => "kilo_run",
        "input_summary" => prompt.truncate(OUTPUT_SUMMARY_LIMIT),
        "output_summary" => output.truncate(OUTPUT_SUMMARY_LIMIT),
        "duration_ms" => submitter_result.duration_ms,
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0,
        "metadata" => {
          "exit_status" => submitter_result.exit_status,
          "command" => command
        }.compact
      }
    end
  end
end

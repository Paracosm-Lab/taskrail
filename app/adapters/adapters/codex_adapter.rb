module Adapters
  class CodexAdapter < BaseAdapter
    DEFAULT_COMMAND = "codex"
    DEFAULT_ARGS = ["exec", "--json"].freeze
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    OUTPUT_SUMMARY_LIMIT = 500

    def execute(assignment)
      normalized_assignment = assignment.deep_stringify_keys
      stage = normalized_assignment.fetch("stage")
      config = stage.fetch("adapter_config", {})
      command = config.fetch("command", DEFAULT_COMMAND)
      prompt = CodexAssignmentPrompt.new(normalized_assignment).to_s

      submitter_result = CodexCliSubmitter.new(
        command: command,
        args: config.fetch("args", DEFAULT_ARGS),
        prompt: prompt,
        working_directory: config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY),
        timeout_seconds: normalized_assignment.dig("limits", "timeout_seconds")
      ).call

      trace_events = [trace_event(prompt, submitter_result, command)]

      if submitter_result.exit_status.zero? && submitter_result.external_id.present?
        Engine::AsyncAdapterResult.new(
          provider: "codex",
          external_id: submitter_result.external_id,
          status: "submitted",
          metadata: async_metadata(submitter_result, config),
          trace_events: trace_events
        )
      else
        AgentResult.failure(
          report: failure_report(submitter_result),
          artifacts: [],
          trace_events: trace_events
        )
      end
    end

    private

    def async_metadata(submitter_result, config)
      submitter_result.metadata.merge(
        "exit_status" => submitter_result.exit_status,
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "output_artifact_kind" => config.fetch("output_artifact_kind", "branch"),
        "branch_prefix" => config["branch_prefix"]
      ).compact
    end

    def failure_report(submitter_result)
      reason = submitter_result.exit_status.zero? ? "missing external id" : "failed"
      {
        "summary" => "Codex submission #{reason}",
        "stdout" => submitter_result.stdout,
        "stderr" => submitter_result.stderr,
        "exit_status" => submitter_result.exit_status
      }
    end

    def trace_event(prompt, submitter_result, command)
      output = [submitter_result.stdout, submitter_result.stderr].reject(&:blank?).join("\n")
      {
        "event_type" => "codex_submit",
        "input_summary" => prompt.truncate(OUTPUT_SUMMARY_LIMIT),
        "output_summary" => output.truncate(OUTPUT_SUMMARY_LIMIT),
        "duration_ms" => submitter_result.duration_ms,
        "tokens_in" => 0,
        "tokens_out" => 0,
        "cost_cents" => 0,
        "metadata" => {
          "exit_status" => submitter_result.exit_status,
          "command" => command,
          "external_id" => submitter_result.external_id
        }.compact
      }
    end
  end
end

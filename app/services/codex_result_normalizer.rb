class CodexResultNormalizer
  OUTPUT_SUMMARY_LIMIT = 500

  def initialize(claim:, poll_result:)
    @claim = claim
    @poll_result = poll_result
  end

  def call
    if poll_result.status == "succeeded"
      AgentResult.success(
        report: success_report,
        artifacts: branch_artifacts,
        trace_events: [trace_event]
      )
    else
      AgentResult.failure(
        report: failure_report,
        artifacts: [],
        trace_events: [trace_event]
      )
    end
  end

  private

  attr_reader :claim, :poll_result

  def success_report
    metadata_report = poll_result.metadata.fetch("report", {})
    {
      "summary" => metadata_report.fetch("summary", "Codex run completed"),
      "stdout" => poll_result.stdout,
      "stage" => stage_name
    }
  end

  def failure_report
    {
      "summary" => "Codex run failed",
      "stdout" => poll_result.stdout,
      "stderr" => poll_result.stderr,
      "exit_status" => poll_result.exit_status,
      "stage" => stage_name
    }
  end

  def branch_artifacts
    configured_artifacts = poll_result.metadata.fetch("artifacts", [])
    branch_artifacts = configured_artifacts.select { |artifact| artifact["kind"] == "branch" && artifact.dig("data", "name").present? }
    return branch_artifacts if branch_artifacts.any?

    branch_name = poll_result.metadata["branch"] || poll_result.metadata.dig("artifact", "branch")
    return [] if branch_name.blank?

    [{ "kind" => "branch", "data" => { "name" => branch_name } }]
  end

  def trace_event
    output = [poll_result.stdout, poll_result.stderr].reject(&:blank?).join("\n")
    {
      "event_type" => "codex_complete",
      "input_summary" => async_metadata.to_json.truncate(OUTPUT_SUMMARY_LIMIT),
      "output_summary" => output.truncate(OUTPUT_SUMMARY_LIMIT),
      "duration_ms" => poll_result.duration_ms,
      "tokens_in" => 0,
      "tokens_out" => 0,
      "cost_cents" => 0,
      "metadata" => {
        "status" => poll_result.status,
        "exit_status" => poll_result.exit_status,
        "external_id" => async_metadata["external_id"],
        "model" => claim.assignment["model"]
      }.compact
    }
  end

  def stage_name
    claim.assignment.dig("stage", "name") || claim.work_item.stage_name
  end

  def async_metadata
    claim.assignment.fetch("async", {})
  end
end

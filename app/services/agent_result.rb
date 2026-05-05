class AgentResult
  attr_reader :status, :report, :artifacts, :trace_events, :blocked_question

  def self.success(report:, artifacts: [], trace_events: [])
    new(
      status: "success",
      report: report,
      artifacts: artifacts,
      trace_events: trace_events
    )
  end

  def self.failure(report:, artifacts: [], trace_events: [])
    new(
      status: "failure",
      report: report,
      artifacts: artifacts,
      trace_events: trace_events
    )
  end

  def self.blocked(question:, report: {}, artifacts: [], trace_events: [])
    new(
      status: "blocked",
      report: report,
      artifacts: artifacts,
      trace_events: trace_events,
      blocked_question: question
    )
  end

  def initialize(status:, report:, artifacts:, trace_events:, blocked_question: nil)
    @status = status
    @report = report
    @artifacts = artifacts
    @trace_events = trace_events
    @blocked_question = blocked_question
  end
end

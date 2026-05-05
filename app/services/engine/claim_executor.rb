module Engine
  class ClaimExecutor
    class UnknownAdapter < StandardError; end

    ADAPTERS = {
      "fake" => Adapters::FakeAdapter,
      "shell_script" => Adapters::ShellScriptAdapter,
      "inline_claude" => Adapters::InlineClaudeAdapter
    }.freeze

    def initialize(claim:, stage_config:)
      @claim = claim
      @stage_config = stage_config
    end

    def call
      @claim.update!(started_at: Time.current) unless @claim.started_at
      assignment = AssignmentBuilder.new(claim: @claim, stage_config: @stage_config).build
      @claim.update!(assignment: assignment.deep_stringify_keys)

      result = adapter.execute(assignment)
      return start_async_result(result) if result.is_a?(Engine::AsyncAdapterResult)

      persist_result(result)
      @claim.update!(status: :completed, completed_at: Time.current)
      result
    rescue UnknownAdapter
      @claim.update!(status: :failed, completed_at: Time.current)
      raise
    rescue StandardError
      @claim.update!(status: :failed, completed_at: Time.current)
      raise
    end

    private

    def adapter
      adapter_class = ADAPTERS[@stage_config.adapter_type]
      raise UnknownAdapter, "unknown adapter: #{@stage_config.adapter_type}" unless adapter_class

      adapter_class.new
    end

    def start_async_result(result)
      @claim.update!(
        status: :active,
        async_execution: true,
        assignment: @claim.assignment.merge(
          "async" => {
            "provider" => result.provider,
            "external_id" => result.external_id,
            "status" => result.status,
            "metadata" => result.metadata
          }
        )
      )
      result
    end

    def persist_result(result)
      report = @claim.reports.create!(
        work_item: @claim.work_item,
        stage_name: @claim.work_item.stage_name,
        status: result.status,
        body: result.report,
        blocked_question: result.blocked_question
      )

      result.artifacts.each do |artifact|
        @claim.artifacts.create!(
          work_item: @claim.work_item,
          kind: artifact.fetch("kind"),
          data: artifact.fetch("data", {})
        )
      end

      trace = @claim.create_trace!(
        work_item: @claim.work_item,
        stage_name: @claim.work_item.stage_name,
        agent_type: @claim.agent_type,
        model: @stage_config.model_override,
        started_at: @claim.started_at,
        completed_at: Time.current,
        total_tokens_in: sum_trace(result.trace_events, "tokens_in"),
        total_tokens_out: sum_trace(result.trace_events, "tokens_out"),
        total_cost_cents: sum_trace(result.trace_events, "cost_cents"),
        total_duration_ms: sum_trace(result.trace_events, "duration_ms")
      )

      result.trace_events.each_with_index do |event, index|
        trace.trace_events.create!(
          sequence: index + 1,
          event_type: event.fetch("event_type"),
          tokens_in: event.fetch("tokens_in", 0),
          tokens_out: event.fetch("tokens_out", 0),
          cost_cents: event.fetch("cost_cents", 0),
          duration_ms: event.fetch("duration_ms", 0),
          input_summary: event["input_summary"],
          output_summary: event["output_summary"],
          metadata: event.fetch("metadata", {})
        )
      end

      report
    end

    def sum_trace(events, key)
      events.sum { |event| event.fetch(key, 0).to_i }
    end
  end
end

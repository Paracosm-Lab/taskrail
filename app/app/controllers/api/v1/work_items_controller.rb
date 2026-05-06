module Api
  module V1
    class WorkItemsController < ApplicationController
      def index
        items = WorkItem.includes(:work_queue).order(:created_at)
        items = items.joins(:work_queue).where(work_queues: { slug: params[:queue] }) if params[:queue].present?
        items = items.where(stage_name: params[:stage]) if params[:stage].present?
        if params[:status].present?
          return render json: { error: "invalid status: #{params[:status]}" }, status: :bad_request unless WorkItem.statuses.key?(params[:status])

          items = items.where(status: params[:status])
        end
        tag_filters.each do |key, value|
          items = items.where("work_items.tags ->> ? = ?", key, value)
        end

        render json: { work_items: items.map { |work_item| serialize(work_item) } }
      end

      def show
        render json: serialize(work_item, include_traces: ActiveModel::Type::Boolean.new.cast(params[:traces]))
      end

      def create
        queue = WorkQueue.find_by!(slug: params.require(:queue))
        item = WorkItem.create!(
          work_queue: queue,
          title: params.require(:title),
          spec_url: params.require(:spec_url),
          stage_name: queue.stages.first,
          status: :pending,
          tags: params.fetch(:tags, {}).to_unsafe_h
        )

        render json: serialize(item), status: :created
      end

      def answer
        item = work_item
        metadata = item.metadata.merge("human_answer" => params.require(:answer))
        metadata.delete("blocked_reason")
        metadata.delete("escalation")
        item.update!(status: :pending, metadata: metadata)
        item.transition_logs.create!(from_stage: item.stage_name, to_stage: item.stage_name, trigger: "human_answer", details: { answer: params[:answer] })

        render json: serialize(item)
      end

      def retry
        item = work_item
        item.update!(status: :pending)
        item.transition_logs.create!(from_stage: item.stage_name, to_stage: item.stage_name, trigger: "manual_retry", details: {})

        render json: serialize(item)
      end

      def cancel
        item = work_item
        item.update!(status: :cancelled)
        item.transition_logs.create!(from_stage: item.stage_name, to_stage: item.stage_name, trigger: "cancelled", details: {})

        render json: serialize(item)
      end

      private

      def work_item
        @work_item ||= WorkItem.find(params[:id])
      end

      def tag_filters
        return {} unless params[:tags].present?

        params[:tags].respond_to?(:to_unsafe_h) ? params[:tags].to_unsafe_h : params[:tags].to_h
      end

      def serialize(item, include_traces: false)
        payload = {
          id: item.id,
          title: item.title,
          spec_url: item.spec_url,
          queue: item.work_queue.slug,
          stage_name: item.stage_name,
          status: item.status,
          tags: item.tags,
          metadata: safe_metadata(item),
          retry_count: item.retry_count,
          regression_count: item.regression_count,
          active_claim: active_claim_summary(item),
          escalation: escalation_summary(item)
        }
        payload[:traces] = trace_summaries(item) if include_traces
        payload
      end

      def active_claim_summary(item)
        claim = item.claims.active.order(created_at: :desc).first
        return nil unless claim

        {
          id: claim.id,
          agent_type: claim.agent_type,
          status: claim.status,
          async_execution: claim.async_execution,
          external_id: claim.assignment.dig("async", "external_id"),
          last_heartbeat_at: claim.last_heartbeat_at&.iso8601,
          heartbeat_message: claim.heartbeat_message,
          heartbeat_stale: claim.heartbeat_stale?
        }
      end

      def safe_metadata(item)
        item.metadata.except("escalation")
      end

      def escalation_summary(item)
        escalation = item.metadata["escalation"]
        return nil unless item.blocked? && escalation.present?

        {
          target: escalation["target"],
          reason: escalation["reason"] || item.metadata["blocked_reason"],
          question: escalation["question"],
          human_action_required: escalation.fetch("human_action_required", item.blocked?)
        }
      end

      def trace_summaries(item)
        item.traces.includes(:trace_events).order(created_at: :asc).map do |trace|
          {
            id: trace.id,
            stage_name: trace.stage_name,
            agent_type: trace.agent_type,
            model: trace.model,
            total_tokens_in: trace.total_tokens_in,
            total_tokens_out: trace.total_tokens_out,
            total_cost_cents: trace.total_cost_cents,
            total_duration_ms: trace.total_duration_ms,
            events: trace.trace_events.order(:sequence).map { |event| trace_event_summary(event) }
          }
        end
      end

      def trace_event_summary(event)
        {
          sequence: event.sequence,
          event_type: event.event_type,
          tokens_in: event.tokens_in,
          tokens_out: event.tokens_out,
          cost_cents: event.cost_cents,
          duration_ms: event.duration_ms,
          input_summary: safe_trace_summary(event.input_summary, redact_always: true),
          output_summary: safe_trace_summary(event.output_summary),
          metadata: safe_trace_metadata(event.metadata)
        }
      end

      def safe_trace_metadata(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), sanitized|
            sanitized[key] = sensitive_trace_key?(key) ? "[REDACTED]" : safe_trace_metadata(child)
          end
        when Array
          value.map { |child| safe_trace_metadata(child) }
        when String
          safe_trace_summary(value)
        else
          value
        end
      end

      def safe_trace_summary(value, redact_always: false)
        return value unless value.is_a?(String)
        return "[REDACTED]" if redact_always && value.present?
        return "[REDACTED]" if value.match?(/(?:api[_-]?key|apikey|secret|password|passwd|token|bearer|authorization|credential)(?:\s|[:=]|$)/i)

        value
      end

      def sensitive_trace_key?(key)
        key.to_s.match?(/(?:prompt|assignment|api[_-]?key|apikey|secret|password|passwd|token|authorization|credential)/i)
      end
    end
  end
end

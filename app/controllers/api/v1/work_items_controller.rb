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
        page_items, meta = paginate(items)
        serialized_items = page_items.map { |work_item| serialize(work_item) }

        render json: { data: serialized_items, work_items: serialized_items, meta: meta }
      end

      def show
        render json: serialize(work_item, include_traces: ActiveModel::Type::Boolean.new.cast(params[:traces]))
      end

      def create
        queue = WorkQueue.find_by!(slug: params.require(:queue))
        stage_name = params[:stage_name].presence || queue.stages.first
        unless queue.stage_configs.exists?(stage_name: stage_name)
          return render json: { error: "Stage '#{stage_name}' does not exist in queue '#{queue.slug}'" }, status: :unprocessable_entity
        end

        spec_url = params.require(:spec_url)
        return render(json: { error: "spec_url is too long (max 2 KB)" }, status: :unprocessable_entity) if spec_url.to_s.bytesize > 2.kilobytes

        tags = sanitize_tags(params.fetch(:tags, {}))
        tag_error = validate_tags(tags)
        return render(json: { error: tag_error }, status: :unprocessable_entity) if tag_error

        item = WorkItem.create!(
          work_queue: queue,
          title: params.require(:title),
          spec_url: spec_url,
          stage_name: stage_name,
          status: :pending,
          tags: tags
        )

        render json: serialize(item), status: :created
      end

      def answer
        item = work_item
        answer = params.require(:answer).to_s
        return render(json: { error: "answer is too long (max 64 KB)" }, status: :unprocessable_entity) if answer.bytesize > 64.kilobytes

        metadata = item.metadata.merge("human_answer" => answer)
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

        sanitize_tags(params[:tags])
      end

      def sanitize_tags(raw_tags)
        return {} unless raw_tags.is_a?(ActionController::Parameters) || raw_tags.is_a?(Hash)

        raw_tags.each_pair.each_with_object({}) do |(key, value), tags|
          next unless key.is_a?(String) || key.is_a?(Symbol)

          tags[key.to_s] = value.to_s
        end
      end

      def validate_tags(tags)
        oversized_key = tags.find { |_key, value| value.bytesize > 256 }&.first
        return "tag value for '#{oversized_key}' is too long (max 256 characters)" if oversized_key

        nil
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
        TraceRedactor.safe_metadata(value)
      end

      def safe_trace_summary(value, redact_always: false)
        redacted = TraceRedactor.safe_summary(value, redact_always:)
        return "[REDACTED]" if value.is_a?(String) && redacted != value

        redacted
      end

      def sensitive_trace_key?(key)
        TraceRedactor.sensitive_key?(key)
      end
    end
  end
end

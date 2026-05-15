module Api
  module V1
    class StreamsController < ApplicationController
      include ActionController::Live

      POLL_SECONDS = 2

      def show
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        queue = queue_slug
        loop do
          payload = dashboard_payload(queue)
          response.stream.write("event: dashboard\n")
          response.stream.write("data: #{JSON.dump(payload)}\n\n")
          sleep POLL_SECONDS
        end
      rescue IOError, ActionController::Live::ClientDisconnected
        nil
      ensure
        response.stream.close
      end

      private

      def queue_slug
        return params[:queue] if params[:queue].present?

        WorkQueue.order(:created_at).limit(1).pick(:slug) || raise(ActiveRecord::RecordNotFound, "No queues found")
      end

      def dashboard_payload(queue_slug)
        queue = WorkQueue.find_by!(slug: queue_slug)
        stages = queue.stages.map do |stage_name|
          config = queue.stage_configs.find_by(stage_name: stage_name)
          { name: stage_name, adapter_type: config&.adapter_type, completion_criteria: config&.completion_criteria || [] }
        end

        {
          queue: { id: queue.id, name: queue.name, slug: queue.slug, stages: queue.stages },
          stages: stages,
          work_items: WorkItem.includes(:work_queue, :claims).where(work_queue: queue).order(:created_at).map { |item| serialize_work_item(item) },
          today_costs: totals(Trace.where(created_at: Time.zone.today.beginning_of_day..)),
          total_costs: totals(Trace.all)
        }
      end

      def serialize_work_item(item)
        {
          id: item.id,
          title: item.title,
          spec_url: item.spec_url,
          queue: item.work_queue.slug,
          stage_name: item.stage_name,
          status: item.status,
          tags: item.tags,
          metadata: item.metadata.except("escalation"),
          retry_count: item.retry_count,
          regression_count: item.regression_count,
          active_claim: active_claim_summary(item),
          escalation: escalation_summary(item)
        }
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

      def totals(scope)
        {
          total_tokens_in: scope.sum(:total_tokens_in),
          total_tokens_out: scope.sum(:total_tokens_out),
          total_cost_cents: scope.sum(:total_cost_cents),
          total_duration_ms: scope.sum(:total_duration_ms)
        }
      end
    end
  end
end

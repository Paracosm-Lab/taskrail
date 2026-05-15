module Api
  module V1
    class CostsController < ApplicationController
      def index
        scope = Trace.all
        scope = scope.where(created_at: Time.zone.today.beginning_of_day..) if params[:period] == "today"
        traces, meta = paginate(scope.order(created_at: :desc))

        render json: totals(scope).merge(data: traces.map { |trace| trace_json(trace) }, traces: traces.map { |trace| trace_json(trace) }, meta: meta)
      end

      def work_item
        item = WorkItem.find(params[:id])
        render json: totals(item.traces)
      end

      private

      def totals(scope)
        {
          total_tokens_in: scope.sum(:total_tokens_in),
          total_tokens_out: scope.sum(:total_tokens_out),
          total_cost_cents: scope.sum(:total_cost_cents),
          total_duration_ms: scope.sum(:total_duration_ms)
        }
      end

      def trace_json(trace)
        {
          id: trace.id,
          work_item_id: trace.work_item_id,
          claim_id: trace.claim_id,
          stage_name: trace.stage_name,
          agent_type: trace.agent_type,
          total_tokens_in: trace.total_tokens_in,
          total_tokens_out: trace.total_tokens_out,
          total_cost_cents: trace.total_cost_cents,
          total_duration_ms: trace.total_duration_ms,
          created_at: trace.created_at.iso8601
        }
      end
    end
  end
end

module Api
  module V1
    class CostsController < ApplicationController
      def index
        scope = Trace.all
        scope = scope.where(created_at: Time.zone.today.beginning_of_day..) if params[:period] == "today"

        render json: totals(scope)
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
    end
  end
end

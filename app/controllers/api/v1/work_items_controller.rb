module Api
  module V1
    class WorkItemsController < ApplicationController
      def index
        items = WorkItem.includes(:work_queue).order(:created_at)
        items = items.joins(:work_queue).where(work_queues: { slug: params[:queue] }) if params[:queue].present?
        items = items.where(stage_name: params[:stage]) if params[:stage].present?

        render json: { work_items: items.map { |work_item| serialize(work_item) } }
      end

      def show
        render json: serialize(work_item)
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

      def serialize(item)
        {
          id: item.id,
          title: item.title,
          spec_url: item.spec_url,
          queue: item.work_queue.slug,
          stage_name: item.stage_name,
          status: item.status,
          tags: item.tags,
          metadata: item.metadata,
          retry_count: item.retry_count,
          regression_count: item.regression_count
        }
      end
    end
  end
end

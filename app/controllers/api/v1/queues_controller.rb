module Api
  module V1
    class QueuesController < ApplicationController
      def index
        render json: { queues: WorkQueue.order(:created_at).map { |queue| serialize_queue(queue) } }
      end

      def stages
        queue = WorkQueue.find_by!(slug: params[:slug])
        render json: {
          queue: serialize_queue(queue),
          stages: queue.stages.map { |stage_name| serialize_stage(queue, stage_name) }
        }
      end

      private

      def serialize_queue(queue)
        { id: queue.id, name: queue.name, slug: queue.slug, stages: queue.stages }
      end

      def serialize_stage(queue, stage_name)
        config = queue.stage_configs.find_by(stage_name: stage_name)
        { name: stage_name, adapter_type: config&.adapter_type, completion_criteria: config&.completion_criteria || [] }
      end
    end
  end
end

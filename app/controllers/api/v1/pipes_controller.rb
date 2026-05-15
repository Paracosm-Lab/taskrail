module Api
  module V1
    class PipesController < ApplicationController
      def index
        pipes = Pipe.includes(:from_queue, :to_queue).order(:name)
        page_pipes, meta = paginate(pipes)
        serialized_pipes = page_pipes.map { |pipe| pipe_json(pipe) }

        render json: { data: serialized_pipes, pipes: serialized_pipes, meta: meta }
      end

      def show
        pipe = Pipe.includes(:from_queue, :to_queue).find_by(slug: params[:slug])
        if pipe
          render json: pipe_json(pipe)
        else
          render json: { error: "Pipe not found" }, status: :not_found
        end
      end

      private

      def pipe_json(pipe)
        {
          slug: pipe.slug,
          name: pipe.name,
          enabled: pipe.enabled,
          from: { queue: pipe.from_queue.slug, stage: pipe.from_stage },
          to: { queue: pipe.to_queue.slug, stage: pipe.to_stage },
          when_config: pipe.when_config,
          transform_config: pipe.transform_config,
          limits: pipe.limits
        }
      end
    end
  end
end

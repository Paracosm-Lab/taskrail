module Web
  class QueuesController < BaseController
    before_action :set_queue, only: [:show, :board]

    def index
      @queues = WorkQueue.order(:slug).map do |q|
        counts = q.work_items.group(:status).count
        { queue: q, counts: counts }
      end
    end

    def show
      @work_items_by_stage = grouped_work_items
    end

    def board
      @work_items_by_stage = grouped_work_items
      render partial: "board"
    end

    private

    def set_queue
      @queue = WorkQueue.find_by(slug: params[:slug])
      render plain: "Queue not found", status: :not_found unless @queue
    end

    def grouped_work_items
      @queue.work_items
        .where.not(status: :completed)
        .order(updated_at: :desc)
        .group_by(&:stage_name)
        .merge(
          @queue.work_items
            .where(status: :completed)
            .order(updated_at: :desc)
            .limit(10)
            .group_by(&:stage_name)
        )
    end
  end
end

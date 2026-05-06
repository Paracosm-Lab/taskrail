module Web
  class WorkItemsController < BaseController
    before_action :set_work_item, only: [:show, :retry, :cancel]

    def show
      @queue = @work_item.work_queue
      @claims = @work_item.claims.includes(:trace, :reports, :artifacts).order(:created_at)
      @artifacts = @work_item.artifacts.order(created_at: :desc)
      @transition_logs = @work_item.transition_logs.order(:created_at)
      @children = @work_item.children.includes(:work_queue).order(:created_at)
    end

    def new
      @queue = params[:queue] ? WorkQueue.find_by(slug: params[:queue]) : WorkQueue.order(:slug).first
      @queues = WorkQueue.order(:slug)
      @work_item = WorkItem.new
    end

    def create
      queue = WorkQueue.find_by(slug: params[:work_item][:queue_slug])
      return render plain: "Queue not found", status: :not_found unless queue

      @work_item = WorkItem.new(
        work_queue: queue,
        title: params[:work_item][:title],
        spec_url: params[:work_item][:spec_url],
        stage_name: queue.stages.first,
        tags: parse_tags(params[:work_item][:tags])
      )

      if @work_item.save
        redirect_to work_item_path(@work_item), notice: "Work item created"
      else
        @queues = WorkQueue.order(:slug)
        @queue = queue
        render :new, status: :unprocessable_entity
      end
    end

    def retry
      @work_item.update!(status: :pending)
      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "manual_retry"
      )
      redirect_to work_item_path(@work_item), notice: "Work item queued for retry"
    end

    def cancel
      @work_item.update!(status: :cancelled)
      redirect_to work_item_path(@work_item), notice: "Work item cancelled"
    end

    private

    def set_work_item
      @work_item = WorkItem.find_by(id: params[:id])
      render(plain: "Work item not found", status: :not_found) and return unless @work_item
    end

    def parse_tags(tags_param)
      return {} if tags_param.blank?
      # Accept array of {name:, value:} pairs from form
      tags = {}
      Array(tags_param).each do |pair|
        name = pair[:name].to_s.strip
        value = pair[:value].to_s.strip
        tags[name] = value if name.present?
      end
      tags
    end
  end
end

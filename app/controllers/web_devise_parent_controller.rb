class WebDeviseParentController < ActionController::Base
  layout "web"

  private

  def queues_by_category
    @queues_by_category ||= WorkQueue.order(:category, :name)
                                     .group_by { |queue| queue.category || "Uncategorized" }
  end
  helper_method :queues_by_category
end

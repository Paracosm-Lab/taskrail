module Web
  class BaseController < ActionController::Base
    layout "web"
    before_action :authenticate_user!

    private

    def queues_by_category
      @queues_by_category ||= WorkQueue.order(:category, :name)
                                       .group_by { |q| q.category || "Uncategorized" }
    end
    helper_method :queues_by_category
  end
end

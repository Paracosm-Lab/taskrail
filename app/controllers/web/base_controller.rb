module Web
  class BaseController < ActionController::Base
    layout "web"

    private

    def all_queues
      WorkQueue.order(:slug)
    end
    helper_method :all_queues
  end
end

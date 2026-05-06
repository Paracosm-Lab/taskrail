module Web
  class PipesController < BaseController
    def index
      @pipes = Pipe.includes(:from_queue, :to_queue).order(:name)
    end
  end
end

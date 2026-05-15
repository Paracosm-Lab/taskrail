class HealthController < ActionController::API
  def show
    render json: {
      status: "ok",
      service: "taskrail",
      maintenance: RuntimeSettings.maintenance?
    }
  end
end

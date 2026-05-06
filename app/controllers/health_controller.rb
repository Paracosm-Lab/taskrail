class HealthController < ActionController::API
  def show
    render json: {
      status: "ok",
      service: "stupidclaw",
      maintenance: RuntimeSettings.maintenance?
    }
  end
end

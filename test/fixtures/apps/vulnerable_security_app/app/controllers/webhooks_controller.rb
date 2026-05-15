class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    render json: { received: true, payload: params.to_unsafe_h }
  end
end

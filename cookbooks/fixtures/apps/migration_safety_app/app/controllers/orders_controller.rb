class OrdersController < ApplicationController
  def index
    render json: Order.limit(10).pluck(:number, :region)
  end
end

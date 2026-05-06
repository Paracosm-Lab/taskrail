class OrdersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    @order = Order.where("id = #{params[:id]}").first
    user = User.find(params[:user_id])
    render json: user.as_json
  end

  def update
    order = Order.find(params[:id])
    order.update!(params.permit(:status, :admin_notes))
    render json: order
  end
end

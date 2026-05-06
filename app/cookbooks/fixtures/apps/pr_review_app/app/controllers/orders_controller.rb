class OrdersController < ApplicationController
  def index
    @orders = OrderSearch.new.safe_search(params[:q])
  end

  def create
    @order = Order.create!(order_params.merge(user: current_user))
  end

  def destroy
    Order.find(params[:id]).destroy!
  end

  private

  def order_params
    params.require(:order).permit(:name, :total_cents)
  end
end

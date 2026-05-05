class OrdersController < ApplicationController
  def create
    puts params.inspect
    OrderCreator.call(params: params)
    head :accepted
  end
end

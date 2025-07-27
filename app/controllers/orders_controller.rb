# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [:show]

  def index
    @orders = Order.includes(:client, :seller, :order_items).order(created_at: :desc).page(params[:page])
  end

  def show
    # @order ya está seteado
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end
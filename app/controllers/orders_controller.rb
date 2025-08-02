# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [ :show, :destroy ]

  def index
    @q = Order.ransack(params[:q])
    @orders = @q.result.includes(:client, :seller, :order_items).order(created_at: :desc).page(params[:page])
    authorize @orders
  end

  def show
    authorize @order
  end

  def destroy
    authorize @order
    @order.destroy
    redirect_to orders_path, notice: "Pedido eliminado correctamente."
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end

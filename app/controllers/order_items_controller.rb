# app/controllers/order_items_controller.rb
class OrderItemsController < ApplicationController
  before_action :set_order_item, only: [:confirm, :unconfirm]

  def confirm
    authorize @order_item, :confirm?
    @order_item.confirm!
    redirect_back fallback_location: orders_path, notice: "Producto confirmado."
  end

  def unconfirm
    authorize @order_item, :unconfirm?
    @order_item.unconfirm!
    redirect_back fallback_location: orders_path, notice: "Confirmación retirada."
  end

  private

  def set_order_item
    @order_item = OrderItem.find(params[:id])
  end
end

# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [ :show, :destroy, :confirm_all_items_ready ]

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

  def confirm_all_items_ready
    authorize @order, :confirm_all_items_ready?

    updated = @order.order_items.where(status: :in_production).update_all(status: :ready, updated_at: Time.current, confirmed: true)
    @order.check_and_update_status! # Para actualizar el estado del pedido si corresponde

    redirect_to order_path(@order), notice: "#{updated} productos confirmados como listos para entrega."
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end

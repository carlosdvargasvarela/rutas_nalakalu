# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [:show, :destroy, :confirm_all_items_ready]

  def index
    # Incluir las asociaciones necesarias para el filtro de notas
    @q = Order.left_joins(:deliveries, order_items: :order_item_notes)
      .ransack(params[:q])

    # Usar distinct porque un pedido puede tener varias deliveries/notas
    @orders = @q.result
      .includes(:client, :seller, :deliveries, order_items: :order_item_notes)
      .distinct
      .order(created_at: :desc)
      .page(params[:page])
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

    order_items_to_confirm = @order.order_items.where(status: :in_production)

    order_items_to_confirm.each do |item|
      item.update!(status: :ready, confirmed: true) # aquí sí cambia el objeto en memoria
    end

    @order.check_and_update_status!
    redirect_to order_path(@order), notice: "#{order_items_to_confirm.size} productos confirmados como listos para entrega."
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end

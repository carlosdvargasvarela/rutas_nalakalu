# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [ :show, :destroy, :confirm_all_items_ready ]

    def index
      # Asociar deliveries en el ransack para que entienda los filtros en base a Deliveries
      @q = Order.joins(:deliveries).ransack(params[:q])

      # Usar distinct porque un pedido puede tener varias deliveries dentro del mismo rango
      @orders = @q.result
                  .includes(:client, :seller, :order_items, :deliveries)
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

# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [:show, :confirm, :mark_delivered, :reschedule, :cancel]

  def show
    @delivery = @delivery_item.delivery
  end

  def confirm
    if @delivery_item.rescheduled?
      redirect_back fallback_location: delivery_path(@delivery_item.delivery), alert: "No se puede modificar un producto reagendado."
      return
    end
    @delivery_item.update!(status: :confirmed)
    @delivery_item.update_delivery_status
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), notice: "Producto confirmado para entrega."
  end

  def mark_delivered
    @delivery_item.mark_as_delivered!
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto marcado como entregado."
  end

  def reschedule
    @delivery_item = DeliveryItem.find(params[:id])

    if params[:new_delivery] == "true"
      @delivery_item.reschedule!(new_date: params[:new_date].presence && Date.parse(params[:new_date]))
      notice = "Producto reagendado en una nueva entrega."
    elsif params[:target_delivery_id].present?
      target_delivery = Delivery.find(params[:target_delivery_id])
      @delivery_item.reschedule!(target_delivery: target_delivery)
      notice = "Producto reagendado en una entrega existente."
    else
      redirect_back fallback_location: delivery_path(@delivery_item.delivery), alert: "Debes seleccionar una opción de reagendado."
      return
    end

    redirect_to delivery_path(@delivery_item.delivery), notice: notice
  end

  def cancel
    @delivery_item.update!(status: :cancelled)
    @delivery_item.update_delivery_status
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto cancelado."
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end
end
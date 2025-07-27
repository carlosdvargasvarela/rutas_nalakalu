# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [:show, :confirm, :mark_delivered, :reschedule, :cancel]

  def show
    @delivery = @delivery_item.delivery
  end

  def confirm
    @delivery_item.update!(status: :confirmed)
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto confirmado para entrega."
  end

  def mark_delivered
    @delivery_item.mark_as_delivered!
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto marcado como entregado."
  end

  def reschedule
    @delivery_item.update!(status: :rescheduled)
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto reprogramado."
  end

  def cancel
    @delivery_item.update!(status: :cancelled)
    redirect_back fallback_location: delivery_path(@delivery_item.delivery), 
                  notice: "Producto cancelado."
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end
end
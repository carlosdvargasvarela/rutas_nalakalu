# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [:show, :confirm, :mark_delivered, :reschedule, :cancel, :update_notes]

  def show
    @delivery = @delivery_item.delivery
  end

  def confirm
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :confirmed,
      current_user: current_user
    ).call

    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
      notice: "Producto confirmado para entrega."
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def mark_delivered
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :delivered,
      current_user: current_user
    ).call

    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
      notice: "Producto marcado como entregado."
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def reschedule
    DeliveryItems::Rescheduler.new(
      delivery_item: @delivery_item,
      params: params,
      current_user: current_user
    ).call

    notice = (params[:new_delivery] == "true") ?
      "Producto reagendado en una nueva entrega." :
      "Producto reagendado en una entrega existente."

    redirect_to delivery_path(@delivery_item.delivery), notice: notice
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery), prefix: "Error al reagendar")
  end

  def cancel
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :cancelled,
      current_user: current_user
    ).call

    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
      notice: "Producto cancelado."
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def update_notes
    authorize @delivery_item if respond_to?(:authorize)

    DeliveryItems::NotesUpdater.new(
      delivery_item: @delivery_item,
      note_text: notes_params[:notes],
      current_user: current_user
    ).call

    redirect_back fallback_location: delivery_plan_path(@delivery_item.delivery.delivery_plan),
      notice: "Nota actualizada correctamente."
  rescue => e
    handle_item_error(e, fallback: delivery_plan_path(@delivery_item.delivery.delivery_plan),
      prefix: "Error al actualizar la nota")
  end

  def bulk_add_notes
    delivery = Delivery.find(params[:delivery_id])
    delivery_plan = delivery.delivery_plan
    authorize delivery, :update? if respond_to?(:authorize)

    DeliveryItems::NotesUpdater.new(
      delivery: delivery,
      note_text: params.dig(:note, :body),
      target: params[:target],
      current_user: current_user
    ).call

    notice = (params[:target] == "all") ?
      "Nota agregada a todos los productos de la entrega." :
      "Nota agregada al producto."

    if !delivery_plan.nil?
      redirect_back fallback_location: delivery_plan_path(delivery.delivery_plan), notice: notice
    else
      redirect_back fallback_location: delivery_path(delivery), notice: notice
    end
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: delivery_plans_path,
      alert: "Entrega o producto no encontrado."
  rescue => e
    handle_item_error(e, fallback: delivery_plan_path(delivery.delivery_plan))
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def notes_params
    params.require(:delivery_item).permit(:notes)
  end

  # 🔹 Handler centralizado
  def handle_item_error(exception, fallback:, prefix: nil)
    message = prefix.present? ? "#{prefix}: #{exception.message}" : exception.message
    Rails.logger.error("❌ Error DeliveryItemsController: #{message}")
    redirect_back fallback_location: fallback, alert: message
  end
end

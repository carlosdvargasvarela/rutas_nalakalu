# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [:show, :confirm, :mark_delivered, :reschedule, :cancel, :update_notes]

  def show
    @delivery = @delivery_item.delivery
  end

  def confirm
    authorize DeliveryItem, :confirm?
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :confirmed,
      current_user: current_user
    ).call

    respond_to do |format|
      format.turbo_stream do
        @delivery_item.reload
        render turbo_stream: turbo_stream.replace(
          dom_id(@delivery_item),
          partial: "deliveries/show_partials/product_item",
          locals: {item: @delivery_item, delivery: @delivery_item.delivery}
        )
      end
      format.html do
        redirect_back fallback_location: delivery_path(@delivery_item.delivery),
          notice: "Producto confirmado para entrega."
      end
    end
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def mark_delivered
    authorize DeliveryItem, :confirm?
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :delivered,
      current_user: current_user
    ).call

    respond_to do |format|
      format.turbo_stream do
        @delivery_item.reload
        render turbo_stream: turbo_stream.replace(
          dom_id(@delivery_item),
          partial: "deliveries/show_partials/product_item",
          locals: {item: @delivery_item, delivery: @delivery_item.delivery}
        )
      end
      format.html do
        redirect_back fallback_location: delivery_path(@delivery_item.delivery),
          notice: "Producto marcado como entregado."
      end
    end
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def reschedule
    authorize DeliveryItem, :confirm?
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
    authorize DeliveryItem, :confirm?
    DeliveryItems::StatusUpdater.new(
      delivery_item: @delivery_item,
      new_status: :cancelled,
      current_user: current_user
    ).call

    respond_to do |format|
      format.turbo_stream do
        @delivery_item.reload
        render turbo_stream: turbo_stream.replace(
          dom_id(@delivery_item),
          partial: "deliveries/show_partials/product_item",
          locals: {item: @delivery_item, delivery: @delivery_item.delivery}
        )
      end
      format.html do
        redirect_back fallback_location: delivery_path(@delivery_item.delivery),
          notice: "Producto cancelado."
      end
    end
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery))
  end

  def update_notes
    authorize DeliveryItem, :confirm?
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
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])
    delivery_plan = delivery.delivery_plan

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

  def bulk_confirm
    authorize DeliveryItem, :confirm?
    items = DeliveryItem.where(id: params[:item_ids], status: :pending)
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :confirmed,
        current_user: current_user
      ).call
    end

    delivery = Delivery.find(params[:delivery_id])
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "delivery_items_list",
            partial: "deliveries/show_partials/product_table",
            locals: {delivery: delivery.reload}
          )
        ]
      end
      format.html { redirect_back fallback_location: delivery_path(delivery), notice: "Items confirmados." }
    end
  end

  def bulk_deliver
    authorize DeliveryItem, :confirm?
    items = DeliveryItem.where(id: params[:item_ids])
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :delivered,
        current_user: current_user
      ).call
    end

    delivery = Delivery.find(params[:delivery_id])
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "delivery_items_list",
            partial: "deliveries/show_partials/product_table",
            locals: {delivery: delivery.reload}
          )
        ]
      end
      format.html { redirect_back fallback_location: delivery_path(delivery), notice: "Items marcados como entregados." }
    end
  end

  def bulk_cancel
    authorize DeliveryItem, :confirm?
    items = DeliveryItem.where(id: params[:item_ids])
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :cancelled,
        current_user: current_user
      ).call
    end

    delivery = Delivery.find(params[:delivery_id])
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "delivery_items_list",
            partial: "deliveries/show_partials/product_table",
            locals: {delivery: delivery.reload}
          )
        ]
      end
      format.html { redirect_back fallback_location: delivery_path(delivery), notice: "Items cancelados." }
    end
  end

  def bulk_reschedule
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])  # ← mover ARRIBA del items
    items = DeliveryItem.where(id: params[:item_ids])

    items.each do |item|
      DeliveryItems::Rescheduler.new(
        delivery_item: item,
        params: params,
        current_user: current_user
      ).call
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "delivery_items_list",
            partial: "deliveries/show_partials/product_table",
            locals: {delivery: delivery.reload}
          )
        ]
      end
      format.html { redirect_back fallback_location: delivery_path(delivery), notice: "Items reagendados." }
    end
  rescue => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash_messages",
          partial: "shared/flash",
          locals: {alert: e.message}
        )
      end
      format.html { redirect_back fallback_location: delivery_path(delivery), alert: e.message }
    end
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def notes_params
    params.require(:delivery_item).permit(:notes)
  end

  def handle_item_error(exception, fallback:, prefix: nil)
    message = prefix.present? ? "#{prefix}: #{exception.message}" : exception.message
    Rails.logger.error("❌ Error DeliveryItemsController: #{message}")
    redirect_back fallback_location: fallback, alert: message
  end
end

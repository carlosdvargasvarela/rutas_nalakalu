# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  include ActionView::RecordIdentifier

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

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Producto confirmado para entrega.")
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

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Producto marcado como entregado.")
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

    delivery = @delivery_item.delivery.reload

    notice = if params[:new_delivery] == "true"
      "Producto reagendado en una nueva entrega."
    else
      "Producto reagendado en una entrega existente."
    end

    respond_with_delivery_update(delivery, notice: notice)
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

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Producto cancelado.")
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

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Nota actualizada correctamente.")
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery),
      prefix: "Error al actualizar la nota")
  end

  def bulk_add_notes
    authorize DeliveryItem, :confirm?

    delivery = Delivery.find(params[:delivery_id])

    DeliveryItems::NotesUpdater.new(
      delivery: delivery,
      note_text: params.dig(:note, :body),
      target: params[:target],
      current_user: current_user
    ).call

    notice = if params[:target] == "all"
      "Nota agregada a todos los productos de la entrega."
    else
      "Nota agregada al producto."
    end

    respond_with_delivery_update(delivery.reload, notice: notice)
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: delivery_plans_path, alert: "Entrega o producto no encontrado."
  rescue => e
    handle_item_error(e, fallback: delivery_path(params[:delivery_id]))
  end

  def bulk_confirm
    authorize DeliveryItem, :confirm?

    delivery = Delivery.find(params[:delivery_id])
    items = delivery.delivery_items.where(status: :pending)

    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :confirmed,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "Items confirmados.")
  end

  def bulk_deliver
    authorize DeliveryItem, :confirm?

    delivery = Delivery.find(params[:delivery_id])
    items = delivery.delivery_items

    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :delivered,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "Items marcados como entregados.")
  end

  def bulk_cancel
    authorize DeliveryItem, :confirm?

    delivery = Delivery.find(params[:delivery_id])
    items = delivery.delivery_items

    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :cancelled,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "Items cancelados.")
  end

  def bulk_reschedule
    authorize DeliveryItem, :confirm?

    delivery = Delivery.find(params[:delivery_id])
    items = DeliveryItem.where(id: params[:item_ids])

    items.each do |item|
      DeliveryItems::Rescheduler.new(
        delivery_item: item,
        params: params,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "Items reagendados.")
  rescue => e
    handle_item_error(e, fallback: delivery_path(delivery), prefix: "Error al reagendar")
  end

  def reschedule_form
    @delivery_item = DeliveryItem.find(params[:id])
    @delivery = @delivery_item.delivery
    @future_deliveries = Delivery.where(
      delivery_address: @delivery.delivery_address
    ).where("delivery_date >= ?", Date.current).where.not(id: @delivery.id).order(:delivery_date)

    render layout: false
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def notes_params
    params.require(:delivery_item).permit(:notes)
  end

  def respond_with_delivery_update(delivery, notice:)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = notice

        render turbo_stream: [
          turbo_stream.replace(
            "delivery_items_list",
            partial: "deliveries/show_partials/product_table",
            locals: {delivery: delivery}
          ),
          turbo_stream.replace(
            dom_id(delivery, :card_content),
            partial: "deliveries/index_partials/delivery_card_content",
            locals: {delivery: delivery}
          )
        ]
      end

      format.html do
        redirect_back fallback_location: delivery_path(delivery), notice: notice
      end
    end
  end

  def handle_item_error(exception, fallback:, prefix: nil)
    message = prefix.present? ? "#{prefix}: #{exception.message}" : exception.message
    Rails.logger.error("❌ Error DeliveryItemsController: #{message}")

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: [], status: :unprocessable_entity
      end

      format.html do
        redirect_back fallback_location: fallback, alert: message
      end
    end
  end
end

class DeliveryItemsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_delivery_item, only: [
    :show, :confirm, :mark_delivered, :reschedule,
    :cancel, :update_notes, :reschedule_form
  ]

  def show
    authorize @delivery_item, :show?
    @delivery = @delivery_item.delivery
  end

  def reschedule_form
    authorize @delivery_item, :confirm?

    @delivery = @delivery_item.delivery
    @future_deliveries = Delivery
      .where(delivery_address: @delivery.delivery_address)
      .where("delivery_date >= ?", Date.current)
      .where.not(id: @delivery.id)
      .order(:delivery_date)

    render layout: false
  end

  def confirm
    authorize @delivery_item, :confirm?

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
    authorize @delivery_item, :confirm?

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
    authorize @delivery_item, :confirm?

    DeliveryItems::Rescheduler.new(
      delivery_item: @delivery_item,
      params: reschedule_params,
      current_user: current_user
    ).call

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Producto reagendado correctamente.")
  rescue => e
    handle_item_error(e, fallback: delivery_path(@delivery_item.delivery), prefix: "Error al reagendar")
  end

  def cancel
    authorize @delivery_item, :confirm?

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
    authorize @delivery_item, :confirm?

    DeliveryItems::NotesUpdater.new(
      delivery_item: @delivery_item,
      note_text: notes_params[:notes],
      current_user: current_user
    ).call

    delivery = @delivery_item.delivery.reload
    respond_with_delivery_update(delivery, notice: "Nota actualizada correctamente.")
  rescue => e
    handle_item_error(
      e,
      fallback: delivery_path(@delivery_item.delivery),
      prefix: "Error al actualizar la nota"
    )
  end

  def bulk_confirm
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])

    return render_bulk_locked(delivery) if delivery.bulk_locked?

    items = delivery.delivery_items.bulk_confirmable
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :confirmed,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "#{items.count} producto(s) confirmado(s).")
  end

  def bulk_deliver
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])

    return render_bulk_locked(delivery) if delivery.bulk_locked?

    items = delivery.delivery_items.bulk_deliverable
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :delivered,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "#{items.count} producto(s) marcado(s) como entregado(s).")
  end

  def bulk_reschedule_form
    authorize DeliveryItem, :confirm?

    @delivery = Delivery.find(params[:delivery_id])
    # Convertimos el string "524,525" en un array de IDs
    @item_ids = params[:item_ids].to_s.split(",").map(&:strip)

    @items = @delivery.delivery_items
      .where(id: @item_ids)
      .includes(:order_item)

    @future_deliveries = Delivery
      .where(
        order_id: @delivery.order_id,
        delivery_address_id: @delivery.delivery_address_id
      )
      .where("delivery_date >= ?", Date.current)
      .where.not(id: @delivery.id)
      .where.not(status: %i[rescheduled cancelled archived])
      .order(:delivery_date)

    # Usamos layout: false porque Turbo Frame lo insertará en el modal existente
    render layout: false
  end

  def bulk_cancel
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])

    return render_bulk_locked(delivery) if delivery.bulk_locked?

    items = delivery.delivery_items.bulk_cancellable
    items.each do |item|
      DeliveryItems::StatusUpdater.new(
        delivery_item: item,
        new_status: :cancelled,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "#{items.count} producto(s) cancelado(s).")
  end

  def bulk_reschedule
    authorize DeliveryItem, :confirm?
    delivery = Delivery.find(params[:delivery_id])

    return render_bulk_locked(delivery) if delivery.bulk_locked?

    item_ids = params[:item_ids].to_s.split(",").map(&:strip)

    items = delivery.delivery_items
      .bulk_reschedulable
      .where(id: item_ids)

    items.each do |item|
      DeliveryItems::Rescheduler.new(
        delivery_item: item,
        params: params,
        current_user: current_user
      ).call
    end

    respond_with_delivery_update(delivery.reload, notice: "#{items.count} producto(s) reagendado(s).")
  rescue => e
    handle_item_error(e, fallback: delivery_path(delivery), prefix: "Error al reagendar")
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def notes_params
    params.require(:delivery_item).permit(:notes)
  end

  def reschedule_params
    params.permit(:new_delivery, :new_date, :target_delivery_id, :quantity_to_reschedule, :reason)
  end

  def respond_with_delivery_update(delivery, notice:)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = notice

        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update("modal", ""),
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
      format.html { redirect_back fallback_location: deliveries_path, notice: notice }
    end
  end

  def render_bulk_locked(delivery)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Esta entrega no permite acciones masivas en su estado actual."
        render turbo_stream: turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          status: :unprocessable_entity
      end
      format.html do
        redirect_to delivery_path(delivery), alert: "Esta entrega no permite acciones masivas."
      end
    end
  end

  def handle_item_error(exception, fallback:, prefix: nil)
    message = prefix.present? ? "#{prefix}: #{exception.message}" : exception.message
    Rails.logger.error("❌ Error DeliveryItemsController: #{message}")

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: [
          turbo_stream.replace("flash_messages", partial: "layouts/flashes"),
          turbo_stream.update("modal", "")
        ], status: :unprocessable_entity
      end
      format.html do
        redirect_back fallback_location: fallback, alert: message
      end
    end
  end
end

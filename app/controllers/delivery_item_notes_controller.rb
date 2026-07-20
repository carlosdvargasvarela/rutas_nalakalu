class DeliveryItemNotesController < ApplicationController
  include ActionView::RecordIdentifier  # Para usar dom_id en el controller

  before_action :set_delivery_item, only: [:new, :create]
  before_action :set_delivery_item_note, only: [:edit, :update, :destroy, :close, :reopen]
  before_action :authorize_note_action

  def new
    @delivery_item_note = @delivery_item.delivery_item_notes.build
    authorize @delivery_item_note
  end

  def create
    @delivery_item_note = @delivery_item.delivery_item_notes.build(delivery_item_note_params)
    @delivery_item_note.user = current_user
    authorize @delivery_item_note

    if @delivery_item_note.save
      create_notification_for_seller

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Actualizar la lista de notas en la tabla
            turbo_stream.replace(
              dom_id(@delivery_item, :notes),
              partial: "delivery_item_notes/list",
              locals: {item: @delivery_item}
            ),
            # Limpiar el modal
            turbo_stream.update("note_modal", "")
          ]
        end
        format.html { redirect_to order_path(@delivery_item.order_item.order), notice: "Nota agregada correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
    authorize @delivery_item_note
  end

  def update
    authorize @delivery_item_note

    if @delivery_item_note.update(delivery_item_note_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Actualizar la lista de notas en la tabla
            turbo_stream.replace(
              dom_id(@delivery_item_note.delivery_item, :notes),
              partial: "delivery_item_notes/list",
              locals: {item: @delivery_item_note.delivery_item}
            ),
            # Limpiar el modal
            turbo_stream.update("note_modal", "")
          ]
        end
        format.html { redirect_to order_path(@delivery_item_note.delivery_item.order_item.order), notice: "Nota actualizada correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def close
    authorize @delivery_item_note

    if @delivery_item_note.update(closed: true)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@delivery_item_note.delivery_item, :notes),
            partial: "delivery_item_notes/list",
            locals: {item: @delivery_item_note.delivery_item}
          )
        end
        format.html { redirect_to order_path(@delivery_item_note.delivery_item.order_item.order), notice: "Nota cerrada correctamente." }
      end
    else
      redirect_to order_path(@delivery_item_note.delivery_item.order_item.order), alert: "Error al cerrar la nota."
    end
  end

  def reopen
    authorize @delivery_item_note

    if @delivery_item_note.update(closed: false)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@delivery_item_note.delivery_item, :notes),
            partial: "delivery_item_notes/list",
            locals: {item: @delivery_item_note.delivery_item}
          )
        end
        format.html { redirect_to order_path(@delivery_item_note.delivery_item.order_item.order), notice: "Nota reabierta correctamente." }
      end
    else
      redirect_to order_path(@delivery_item_note.delivery_item.order_item.order), alert: "Error al reabrir la nota."
    end
  end

  def destroy
    authorize @delivery_item_note
    delivery_item = @delivery_item_note.delivery_item

    if @delivery_item_note.destroy
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(delivery_item, :notes),
            partial: "delivery_item_notes/list",
            locals: {item: delivery_item}
          )
        end
        format.html { redirect_to order_path(delivery_item.order_item.order), notice: "Nota eliminada correctamente." }
      end
    else
      redirect_to order_path(delivery_item.order_item.order), alert: "Error al eliminar la nota."
    end
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:delivery_item_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to orders_path, alert: "Producto no encontrado."
  end

  def set_delivery_item_note
    @delivery_item_note = DeliveryItemNote.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to orders_path, alert: "Nota no encontrada."
  end

  def delivery_item_note_params
    params.require(:delivery_item_note).permit(:body)
  end

  def authorize_note_action
    unless current_user.production_manager? || current_user.admin?
      redirect_to root_path, alert: "No tienes permisos para realizar esta acción."
      return
    end

    if action_name.in?(%w[edit update destroy close reopen])
      unless @delivery_item_note.user == current_user || current_user.admin?
        redirect_to order_path(@delivery_item_note.delivery_item.order_item.order),
          alert: "Solo puedes editar tus propias notas."
        nil
      end
    end
  end

  def create_notification_for_seller
    return unless @delivery_item_note.persisted?

    seller_user = @delivery_item.order_item.order.seller&.user
    return if seller_user.blank? || seller_user == current_user

    Notification.create!(
      user: seller_user,
      notification_type: "production_note_added",
      notifiable: @delivery_item,
      message: "Se agregó una nota al producto '#{@delivery_item.product}' del pedido ##{@delivery_item.order_item.order.number}"
    )
  rescue => e
    Rails.logger.error "Error creando notificación: #{e.message}"
  end
end

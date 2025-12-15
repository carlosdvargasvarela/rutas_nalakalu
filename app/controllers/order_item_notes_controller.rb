class OrderItemNotesController < ApplicationController
  include ActionView::RecordIdentifier  # Para usar dom_id en el controller

  before_action :set_order_item, only: [:new, :create]
  before_action :set_order_item_note, only: [:edit, :update, :destroy, :close, :reopen]
  before_action :authorize_note_action

  def new
    @order_item = OrderItem.find(params[:order_item_id])
    @order_item_note = @order_item.order_item_notes.build
    authorize @order_item_note
  end

  def create
    @order_item_note = @order_item.order_item_notes.build(order_item_note_params)
    @order_item_note.user = current_user
    authorize @order_item_note

    if @order_item_note.save
      create_notification_for_seller

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Actualizar la lista de notas en la tabla
            turbo_stream.replace(
              dom_id(@order_item, :notes),
              partial: "order_item_notes/list",
              locals: {item: @order_item}
            ),
            # Limpiar el modal
            turbo_stream.update("note_modal", "")
          ]
        end
        format.html { redirect_to order_path(@order_item.order), notice: "Nota agregada correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
    authorize @order_item_note
  end

  def update
    authorize @order_item_note

    if @order_item_note.update(order_item_note_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Actualizar la lista de notas en la tabla
            turbo_stream.replace(
              dom_id(@order_item_note.order_item, :notes),
              partial: "order_item_notes/list",
              locals: {item: @order_item_note.order_item}
            ),
            # Limpiar el modal
            turbo_stream.update("note_modal", "")
          ]
        end
        format.html { redirect_to order_path(@order_item_note.order_item.order), notice: "Nota actualizada correctamente." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def close
    authorize @order_item_note

    if @order_item_note.update(closed: true)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@order_item_note.order_item, :notes),
            partial: "order_item_notes/list",
            locals: {item: @order_item_note.order_item}
          )
        end
        format.html { redirect_to order_path(@order_item_note.order_item.order), notice: "Nota cerrada correctamente." }
      end
    else
      redirect_to order_path(@order_item_note.order_item.order), alert: "Error al cerrar la nota."
    end
  end

  def reopen
    authorize @order_item_note

    if @order_item_note.update(closed: false)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@order_item_note.order_item, :notes),
            partial: "order_item_notes/list",
            locals: {item: @order_item_note.order_item}
          )
        end
        format.html { redirect_to order_path(@order_item_note.order_item.order), notice: "Nota reabierta correctamente." }
      end
    else
      redirect_to order_path(@order_item_note.order_item.order), alert: "Error al reabrir la nota."
    end
  end

  def destroy
    authorize @order_item_note
    order_item = @order_item_note.order_item

    if @order_item_note.destroy
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(order_item, :notes),
            partial: "order_item_notes/list",
            locals: {item: order_item}
          )
        end
        format.html { redirect_to order_path(order_item.order), notice: "Nota eliminada correctamente." }
      end
    else
      redirect_to order_path(order_item.order), alert: "Error al eliminar la nota."
    end
  end

  private

  def set_order_item
    @order_item = OrderItem.find(params[:order_item_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to orders_path, alert: "Producto no encontrado."
  end

  def set_order_item_note
    @order_item_note = OrderItemNote.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to orders_path, alert: "Nota no encontrada."
  end

  def order_item_note_params
    params.require(:order_item_note).permit(:body)
  end

  def authorize_note_action
    unless current_user.production_manager? || current_user.admin?
      redirect_to root_path, alert: "No tienes permisos para realizar esta acción."
      return
    end

    if action_name.in?(%w[edit update destroy close reopen])
      unless @order_item_note.user == current_user || current_user.admin?
        redirect_to order_path(@order_item_note.order_item.order),
          alert: "Solo puedes editar tus propias notas."
        nil
      end
    end
  end

  def create_notification_for_seller
    return unless @order_item_note.persisted?

    seller_user = @order_item.order.seller&.user
    return if seller_user.blank? || seller_user == current_user

    Notification.create!(
      user: seller_user,
      notification_type: "production_note_added",
      notifiable: @order_item,
      message: "Se agregó una nota al producto '#{@order_item.product}' del pedido ##{@order_item.order.number}"
    )
  rescue => e
    Rails.logger.error "Error creando notificación: #{e.message}"
  end
end

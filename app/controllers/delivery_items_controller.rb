# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [ :show, :confirm, :mark_delivered, :reschedule, :cancel, :update_notes ]

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
    if @delivery_item.rescheduled?
      redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                    alert: "No se puede marcar como entregado un producto reagendado."
      return
    end

    @delivery_item.mark_as_delivered!
    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                  notice: "Producto marcado como entregado."
  end

  def reschedule
    @delivery_item = DeliveryItem.find(params[:id])

    if params[:new_delivery] == "true"
      new_date = params[:new_date].presence && Date.parse(params[:new_date])

      # 🔒 Validación para vendedores
      if current_user.role == "seller" && new_date
        unless new_date.wday == Date.today.wday
          redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                      alert: "Los vendedores solo pueden reagendar para #{Date::DAYNAMES[Date.today.wday].downcase}s"
          return
        end
      end

      @delivery_item.reschedule!(new_date: new_date)
      notice = "Producto reagendado en una nueva entrega."

    elsif params[:target_delivery_id].present?
      target_delivery = Delivery.find(params[:target_delivery_id])

      # 🔒 Validación para vendedores - la entrega destino debe ser del mismo día
      if current_user.role == "seller"
        unless target_delivery.delivery_date.wday == Date.today.wday
          redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                      alert: "Solo puedes mover a entregas de #{Date::DAYNAMES[Date.today.wday].downcase}s"
          return
        end
      end

      @delivery_item.reschedule!(target_delivery: target_delivery)
      notice = "Producto reagendado en una entrega existente."
    else
      redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                  alert: "Debes seleccionar una opción de reagendado."
      return
    end

    redirect_to delivery_path(@delivery_item.delivery), notice: notice
  rescue => e
    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                alert: "Error al reagendar: #{e.message}"
  end

  def cancel
    @delivery_item.update!(status: :cancelled)
    @delivery_item.update_delivery_status
    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                  notice: "Producto cancelado."
  end

  def update_notes
    authorize @delivery_item if respond_to?(:authorize) # Pundit si lo usas

    if @delivery_item.update(notes_params)
      redirect_back fallback_location: delivery_plan_path(@delivery_item.delivery.delivery_plan),
                    notice: "Nota actualizada correctamente."
    else
      redirect_back fallback_location: delivery_plan_path(@delivery_item.delivery.delivery_plan),
                    alert: "Error al actualizar la nota."
    end
  end

  def bulk_add_notes
    delivery = Delivery.find(params[:delivery_id])
    authorize delivery, :update? if respond_to?(:authorize) # Pundit si lo usas

    note_text = params.dig(:note, :body)

    if note_text.blank?
      redirect_back fallback_location: delivery_plan_path(delivery.delivery_plan),
                    alert: "La nota no puede estar vacía."
      return
    end

    if params[:target] == "all"
      # Aplicar a todos los delivery_items de la entrega
      delivery.delivery_items.update_all(notes: note_text)
      redirect_back fallback_location: delivery_plan_path(delivery.delivery_plan),
                    notice: "Nota agregada a todos los productos de la entrega."
    else
      # Aplicar solo al delivery_item específico
      item = delivery.delivery_items.find(params[:target])
      if item.update(notes: note_text)
        redirect_back fallback_location: delivery_plan_path(delivery.delivery_plan),
                      notice: "Nota agregada al producto #{item.order_item.product}."
      else
        redirect_back fallback_location: delivery_plan_path(delivery.delivery_plan),
                      alert: "Error al agregar la nota."
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: delivery_plans_path,
                  alert: "Entrega o producto no encontrado."
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end

  def notes_params
    params.require(:delivery_item).permit(:notes)
  end
end

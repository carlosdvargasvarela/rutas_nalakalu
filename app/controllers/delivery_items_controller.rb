# app/controllers/delivery_items_controller.rb
class DeliveryItemsController < ApplicationController
  before_action :set_delivery_item, only: [ :show, :confirm, :mark_delivered, :reschedule, :cancel ]

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
    @delivery_item.update!(status: :pending)
    @delivery_item.update_delivery_status
    redirect_back fallback_location: delivery_path(@delivery_item.delivery),
                  notice: "Producto cancelado."
  end

  private

  def set_delivery_item
    @delivery_item = DeliveryItem.find(params[:id])
  end
end

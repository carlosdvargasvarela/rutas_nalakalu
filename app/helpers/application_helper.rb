# app/helpers/application_helper.rb
module ApplicationHelper
  # Colores para estados de Delivery
  def delivery_status_color(status)
    case status.to_s
    when "scheduled"         then "primary"
    when "in_route"          then "warning"
    when "delivered"         then "success"
    when "rescheduled"       then "info"
    when "cancelled"         then "danger"
    else "secondary"
    end
  end

  # Colores para estados de DeliveryItem
  def delivery_item_status_color(status)
    case status.to_s
    when "pending"           then "secondary"
    when "confirmed"         then "primary"
    when "in_route"          then "warning"
    when "delivered"         then "success"
    when "rescheduled"       then "info"
    when "cancelled"         then "danger"
    else "secondary"
    end
  end

  # Colores para estados de Order (Pedido)
  def order_status_color(status)
    case status.to_s
    when "in_production"     then "info"
    when "ready_for_delivery"then "primary"
    when "delivered"         then "success"
    when "rescheduled"       then "secondary"
    when "cancelled"         then "danger"
    else "secondary"
    end
  end

  # Colores para estados de OrderItem (Producto)
  def order_item_status_color(status)
    case status.to_s
    when "in_production"     then "info"
    when "ready"             then "primary"
    when "delivered"         then "success"
    when "cancelled"         then "danger"
    when "missing"           then "warning"
    else "secondary"
    end
  end

  # Formatea fechas al estilo dd/mm/yyyy
  def format_date_dd_mm_yyyy(date)
    date.strftime("%d/%m/%Y") if date.present?
  end

  # Formatea fechas y horas al estilo dd/mm/yyyy hh:mm
  def format_datetime_dd_mm_yyyy_hh_mm(datetime)
    datetime.strftime("%d/%m/%Y %H:%M") if datetime.present?
  end
end

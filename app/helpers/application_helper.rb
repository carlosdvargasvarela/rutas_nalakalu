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
  def delivery_item_status_color(status_key)
    case status_key.to_s
    when "pending"     then "warning"
    when "confirmed"   then "primary"
    when "in_route"    then "info"
    when "delivered"   then "success"
    when "rescheduled" then "warning"
    when "cancelled"   then "danger"
    else "info"
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

  # Colores para estados de plan de entregas
  def delivery_plan_status_color(status)
    case status.to_s
    when "draft"             then "secondary"
    when "sent_to_logistics" then "info"
    when "routes_created"    then "primary"
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

  def status_badge(status, type = :delivery)
    color = case type
    when :delivery
              {
                "scheduled" => "secondary",
                "ready_to_deliver" => "info",
                "in_route" => "primary",
                "delivered" => "success",
                "rescheduled" => "warning",
                "cancelled" => "danger"
              }[status.to_s] || "secondary"
    when :order
              {
                "pending" => "warning",
                "in_production" => "info",
                "ready_for_delivery" => "primary",
                "delivered" => "success",
                "rescheduled" => "warning",
                "cancelled" => "danger"
              }[status.to_s] || "secondary"
    else
              "secondary"
    end

    label = I18n.t(
      "activerecord.attributes.#{type}.statuses.#{status}",
      default: status.to_s.humanize
    )

    content_tag(:span, label, class: "badge bg-#{color}")
  end
end

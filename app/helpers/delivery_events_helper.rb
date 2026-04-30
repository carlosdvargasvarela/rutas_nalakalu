# app/helpers/delivery_events_helper.rb
module DeliveryEventsHelper
  def delivery_event_description(event)
    data = event.payload_data

    case event.action
    when "rescheduled"
      from = format_date_safe(data["from_date"])
      to = format_date_safe(data["new_date"] || data["to_date"])
      reason = data["reason"].presence
      parts = ["Reagendada"]
      parts << "del #{from}" if from
      parts << "al #{to}" if to
      parts << "— Motivo: #{reason}" if reason
      parts.join(" ")

    when "item_rescheduled"
      product = data["product"].presence || "producto"
      to = format_date_safe(data["new_date"])
      "Ítem «#{product}» movido#{" al #{to}" if to}"

    when "sala_pickup_created"
      count = data["items_count"] || data["item_ids"]&.size || "?"
      sala = data["sala"].presence
      new_id = data["new_delivery_id"]
      parts = ["Recogida en Sala creada para #{count} producto(s)"]
      parts << "en #{sala}" if sala
      parts << "(Entrega ##{new_id})" if new_id
      parts.join(" ")

    when "service_case_created"
      type_label = service_case_type_label(data["delivery_type"])
      count = data["items_count"] || data["item_ids"]&.size || "?"
      new_id = data["new_delivery_id"]
      parts = ["Caso de servicio — #{type_label}"]
      parts << "para #{count} producto(s)"
      parts << "(Entrega ##{new_id})" if new_id
      parts.join(" ")

    when "approved"
      "Aprobada por #{event.actor_name}"

    when "delivered"
      "Marcada como entregada"

    when "warehousing_started"
      until_date = format_date_safe(data["until_date"])
      "Bodegaje iniciado#{" hasta el #{until_date}" if until_date}"

    when "warehousing_ended"
      "Bodegaje finalizado"

    when "seller_reassigned"
      from_s = data["from_seller"].presence
      to_s = data["to_seller"].presence
      if from_s && to_s
        "Vendedor reasignado de #{from_s} a #{to_s}"
      elsif to_s
        "Vendedor asignado: #{to_s}"
      else
        "Vendedor reasignado"
      end

    when "created"
      date = format_date_safe(data["delivery_date"])
      type = data["delivery_type"].presence
      parts = ["Entrega creada"]
      parts << "para el #{date}" if date
      parts << "(#{delivery_type_label(type)})" if type
      parts.join(" ")

    when "updated"
      fields = data["changed_fields"]
      fields.present? ? "Actualizada — campos: #{Array(fields).join(", ")}" : "Entrega actualizada"

    when "cancelled"
      reason = data["reason"].presence
      "Cancelada#{" — #{reason}" if reason}"

    when "archived"
      "Archivada"

    else
      event.label
    end
  end

  private

  def format_date_safe(value)
    return nil if value.blank?
    Date.parse(value.to_s).strftime("%d/%m/%Y")
  rescue ArgumentError
    value.to_s
  end

  def service_case_type_label(type)
    {
      "pickup_with_return" => "Recogida y devolución",
      "return_delivery" => "Devolución",
      "onsite_repair" => "Reparación en sitio",
      "only_pickup" => "Solo recogida"
    }[type.to_s] || type.to_s.humanize
  end

  def delivery_type_label(type)
    {
      "normal" => "Entrega normal",
      "pickup_with_return" => "Recogida con devolución",
      "return_delivery" => "Devolución",
      "onsite_repair" => "Reparación en sitio",
      "only_pickup" => "Solo recogida",
      "internal_delivery" => "Mandado interno"
    }[type.to_s] || type.to_s.humanize
  end

  COLOR_MAP = {
    "primary" => {bg: "#e8f0fe", text: "#3b5bdb", border: "#c5d3f8"},
    "success" => {bg: "#d3f9d8", text: "#2f9e44", border: "#b2f2bb"},
    "danger" => {bg: "#ffe3e3", text: "#c92a2a", border: "#ffc9c9"},
    "warning" => {bg: "#fff3bf", text: "#e67700", border: "#ffec99"},
    "info" => {bg: "#e3fafc", text: "#0c8599", border: "#99e9f2"},
    "secondary" => {bg: "#f1f3f5", text: "#495057", border: "#dee2e6"},
    "dark" => {bg: "#e9ecef", text: "#212529", border: "#ced4da"}
  }.freeze

  def delivery_event_badge_style(event)
    colors = COLOR_MAP.fetch(event.color.to_s, COLOR_MAP["secondary"])
    "background-color:#{colors[:bg]};color:#{colors[:text]};border:1px solid #{colors[:border]};border-radius:6px;padding:3px 8px;"
  end
end

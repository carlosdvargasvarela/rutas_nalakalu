# app/helpers/audit_logs_helper.rb
module AuditLogsHelper
  IGNORED_KEYS = %w[updated_at created_at id].freeze

  # ── Cambios ────────────────────────────────────────────────────────────────

  def summarize_changes(version, max_keys: 5)
    raw = version.object_changes
    return {} if raw.blank?

    changes = raw.is_a?(String) ? JSON.parse(raw) : raw
    return {} unless changes.is_a?(Hash)

    changes.except(*IGNORED_KEYS).first(max_keys).to_h
  rescue JSON::ParserError, StandardError
    {}
  end

  def format_value_detailed(value)
    return "—" if value.nil?
    return "vacío" if value.to_s.strip.empty?
    return value.strftime("%d/%m/%Y %H:%M") if value.is_a?(Time) || value.is_a?(DateTime)
    return value.strftime("%d/%m/%Y") if value.is_a?(Date)
    return value ? "Sí" : "No" if value.is_a?(TrueClass) || value.is_a?(FalseClass)

    value.to_s.truncate(80)
  end

  def change_severity(attr)
    critical = %w[status delivery_date cancelled_at]
    moderate = %w[delivery_type assigned_user_id seller_id]
    if critical.include?(attr.to_s) then "danger"
    elsif moderate.include?(attr.to_s) then "warning"
    else
      "secondary"
    end
  end

  # ── Badges / íconos ────────────────────────────────────────────────────────

  def event_badge(event)
    labels = {"create" => "Creado", "update" => "Actualizado", "destroy" => "Eliminado"}
    colors = {"create" => "success", "update" => "primary", "destroy" => "danger"}
    icons = {"create" => "bi-plus-circle", "update" => "bi-pencil", "destroy" => "bi-trash"}

    label = labels[event] || event.humanize
    color = colors[event] || "secondary"
    icon = icons[event] || "bi-circle"

    content_tag(:span, safe_join([
      content_tag(:i, "", class: "bi #{icon} me-1"),
      label
    ]), class: "badge bg-#{color}-subtle text-#{color}-emphasis",
      style: "font-size:0.72rem;")
  end

  # ── Usuarios ───────────────────────────────────────────────────────────────

  def user_name_for(version, users_by_id = {})
    return "Sistema" if version.whodunnit.blank?

    users_by_id[version.whodunnit.to_s]&.name || "Usuario ##{version.whodunnit}"
  end

  # ── Recurso ────────────────────────────────────────────────────────────────

  def resource_label(version, items_cache = {})
    item = items_cache.dig(version.item_type, version.item_id)
    return "#{version.item_type} ##{version.item_id}" unless item

    if item.respond_to?(:name)
      "#{version.item_type}: #{item.name}"
    elsif item.respond_to?(:order_number)
      "#{version.item_type}: #{item.order_number}"
    else
      "#{version.item_type} ##{version.item_id}"
    end
  end

  def related_context_description(resource)
    case resource
    when Delivery then "Ítems de esta entrega"
    when Order then "Ítems y entregas del pedido"
    when DeliveryPlan then "Asignaciones del plan"
    else "Registros relacionados"
    end
  end

  def format_datetime_cr(time)
    return "—" unless time
    time.in_time_zone("America/Costa_Rica").strftime("%d/%m/%Y %H:%M")
  end

  def safe_find_item(version)
    version.item_type.constantize.find_by(id: version.item_id)
  rescue NameError, StandardError
    nil
  end

  # Ícono Bootstrap según el tipo de modelo
  def resource_icon(item_type)
    icons = {
      "Delivery" => "bi bi-truck",
      "DeliveryItem" => "bi bi-box-seam",
      "Order" => "bi bi-receipt",
      "OrderItem" => "bi bi-list-ul",
      "DeliveryPlan" => "bi bi-calendar3",
      "DeliveryPlanAssignment" => "bi bi-calendar-check",
      "User" => "bi bi-person",
      "Client" => "bi bi-building"
    }
    icons[item_type.to_s] || "bi bi-file-earmark"
  end

  # Etiqueta legible para el registro (intenta order_number, name, o fallback a ID)
  def item_label(version)
    record = safe_find_item(version)

    if record.present?
      if record.respond_to?(:order_number) && record.order_number.present?
        "#{version.item_type} — #{record.order_number}"
      elsif record.respond_to?(:name) && record.name.present?
        "#{version.item_type} — #{record.name}"
      elsif record.respond_to?(:delivery_date)
        "#{version.item_type} ##{version.item_id}"
      else
        "#{version.item_type} ##{version.item_id}"
      end
    else
      "#{version.item_type} ##{version.item_id}"
    end
  end
end

# app/helpers/audit_logs_helper.rb
module AuditLogsHelper
  # Badge con colores según evento
  def event_badge(event)
    case event
    when "create"
      content_tag(:span, class: "badge bg-success") do
        concat content_tag(:i, "", class: "bi bi-plus-circle me-1")
        concat "Creado"
      end
    when "update"
      content_tag(:span, class: "badge bg-primary") do
        concat content_tag(:i, "", class: "bi bi-pencil me-1")
        concat "Actualizado"
      end
    when "destroy"
      content_tag(:span, class: "badge bg-danger") do
        concat content_tag(:i, "", class: "bi bi-trash me-1")
        concat "Eliminado"
      end
    else
      content_tag(:span, event, class: "badge bg-secondary")
    end
  end

  # Nombre del usuario con fallback
  def user_name_for(version, users_by_id)
    return "Sistema" if version.whodunnit.blank?

    user = users_by_id[version.whodunnit]
    user&.name || "Usuario ##{version.whodunnit}"
  end

  # Label descriptivo del recurso
  def item_label(version)
    type = version.item_type
    id = version.item_id

    case type
    when "Order"
      "Pedido ##{id}"
    when "Delivery"
      "Entrega ##{id}"
    when "DeliveryPlan"
      "Plan de entrega ##{id}"
    when "Client"
      "Cliente ##{id}"
    when "Seller"
      "Vendedor ##{id}"
    when "OrderItem"
      "Item de pedido ##{id}"
    when "DeliveryItem"
      "Item de entrega ##{id}"
    else
      "#{type} ##{id}"
    end
  end

  # Buscar el item de forma segura
  def safe_find_item(version)
    version.item_type.constantize.find_by(id: version.item_id)
  rescue NameError, ActiveRecord::RecordNotFound
    nil
  end

  # Flecha de cambio
  def change_arrow
    content_tag(:i, "", class: "bi bi-arrow-right text-muted")
  end

  # Resumir cambios con límite de atributos
  def summarize_changes(version, max_keys: 5)
    return {} if version.object.blank?

    begin
      old_attrs = YAML.safe_load(version.object, permitted_classes: [Time, Date, Symbol, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone])
      current_item = safe_find_item(version)

      return {} unless current_item

      new_attrs = current_item.attributes
      changes = {}

      old_attrs.each do |key, old_value|
        new_value = new_attrs[key]
        next if old_value == new_value
        next if skip_attribute?(key)

        changes[key] = [format_value(old_value), format_value(new_value)]
        break if changes.size >= max_keys
      end

      changes
    rescue => e
      Rails.logger.error "Error al procesar cambios: #{e.message}"
      {}
    end
  end

  # Atributos que no queremos mostrar
  def skip_attribute?(attr)
    %w[created_at updated_at lock_version].include?(attr)
  end

  # Formatear valores para mejor legibilidad
  def format_value(value)
    case value
    when Time, DateTime, ActiveSupport::TimeWithZone
      format_datetime_cr(value)
    when Date
      value.strftime("%d/%m/%Y")
    when TrueClass
      "Sí"
    when FalseClass
      "No"
    when NilClass
      "(vacío)"
    when String
      (value.length > 100) ? "#{value[0..97]}..." : value
    else
      value
    end
  end

  # Icono según tipo de recurso
  def resource_icon(item_type)
    icons = {
      "Order" => "bi-cart-check",
      "Delivery" => "bi-truck",
      "DeliveryPlan" => "bi-calendar-week",
      "Client" => "bi-person",
      "Seller" => "bi-person-badge",
      "OrderItem" => "bi-box-seam",
      "DeliveryItem" => "bi-box",
      "User" => "bi-person-circle"
    }

    icons[item_type] || "bi-file-earmark"
  end

  # Color según tipo de cambio
  def change_severity(attr)
    critical = %w[status approved archived confirmed_by_vendor delivery_date]
    warning = %w[quantity quantity_delivered delivery_type]

    return "danger" if critical.include?(attr)
    return "warning" if warning.include?(attr)
    "info"
  end

  # Color según el tipo de evento
  def event_color(event)
    case event
    when "create" then "success"
    when "update" then "primary"
    when "destroy" then "danger"
    else "secondary"
    end
  end

  # Icono según el tipo de evento
  def event_icon(event)
    case event
    when "create" then "bi-plus-circle"
    when "update" then "bi-pencil"
    when "destroy" then "bi-trash"
    else "bi-question-circle"
    end
  end

  # Formatear valor con más detalle para la vista de timeline
  def format_value_detailed(value)
    case value
    when Time, DateTime, ActiveSupport::TimeWithZone
      format_datetime_cr(value)
    when Date
      value.strftime("%d/%m/%Y")
    when TrueClass
      "✓ Sí"
    when FalseClass
      "✗ No"
    when NilClass
      "(vacío)"
    when String
      value.blank? ? "(vacío)" : value
    when Numeric
      value
    else
      value.to_s
    end
  end
end

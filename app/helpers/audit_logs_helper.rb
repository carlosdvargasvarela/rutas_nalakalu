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

  # ========================================================================
  # 🔹 MÉTODO CLAVE: Resumir cambios usando estados históricos reales
  # ========================================================================
  def summarize_changes(version, max_keys: 5)
    before_attrs =
      case version.event
      when "create"
        {} # no existía antes
      else
        version.reify&.attributes || {}
      end

    after_attrs =
      case version.event
      when "destroy"
        {} # después del destroy ya no hay registro
      else
        state_after(version)
      end

    ignored = %w[id created_at updated_at lock_version]
    keys = (before_attrs.keys + after_attrs.keys).uniq - ignored

    diffs = keys.each_with_object({}) do |attr, h|
      before = before_attrs[attr]
      after = after_attrs[attr]
      next if before == after
      h[attr] = [format_value(before), format_value(after)]
    end

    diffs.first(max_keys).to_h
  rescue => e
    Rails.logger.error "Error al procesar cambios en version #{version.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {}
  end

  # ========================================================================
  # 🔹 Estado "después de este cambio" (histórico real)
  # ========================================================================
  def state_after(version)
    return {} if version.event == "destroy"

    next_version = version.next

    obj =
      if next_version
        # Estado justo antes del siguiente cambio = después de este
        next_version.reify
      else
        # Esta es la última versión → usamos el modelo vivo
        version.item
      end

    obj&.attributes || {}
  rescue => e
    Rails.logger.error "Error al obtener state_after para version #{version.id}: #{e.message}"
    {}
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

# app/helpers/audit_logs_helper.rb
module AuditLogsHelper
  IGNORED_KEYS = %w[updated_at created_at id tracking_token].freeze

  # Etiquetas en español para atributos de todos los modelos auditados
  ATTRIBUTE_LABELS = {
    "status"                   => "Estado",
    "delivery_date"            => "Fecha de entrega",
    "delivery_type"            => "Tipo de entrega",
    "load_status"              => "Estado de carga",
    "contact_name"             => "Nombre de contacto",
    "contact_phone"            => "Teléfono de contacto",
    "delivery_notes"           => "Notas de entrega",
    "delivery_time_preference" => "Horario preferido",
    "reschedule_reason"        => "Motivo de reagendamiento",
    "condominio_number"        => "N° condominio",
    "casa_number"              => "N° casa",
    "confirmed_by_vendor"      => "Confirmado por vendedor",
    "confirmed_by_vendor_at"   => "Fecha confirmación vendedor",
    "warehousing_until"        => "Bodegaje hasta",
    "delivery_address_id"      => "Dirección de entrega",
    "order_id"                 => "Pedido",
    "order_item_id"            => "Ítem de pedido",
    "delivery_id"              => "Entrega",
    "seller_id"                => "Vendedor",
    "client_id"                => "Cliente",
    "assigned_user_id"         => "Usuario asignado",
    "delivery_plan_id"         => "Plan de entregas",
    "product"                  => "Producto",
    "quantity"                 => "Cantidad pedida",
    "quantity_delivered"       => "Cantidad a entregar",
    "confirmed"                => "Confirmado",
    "service_case"             => "Caso de servicio",
    "number"                   => "N° de pedido",
    "name"                     => "Nombre",
    "email"                    => "Correo electrónico",
    "role"                     => "Rol",
    "address"                  => "Dirección",
    "latitude"                 => "Latitud",
    "longitude"                => "Longitud",
    "plus_code"                => "Plus Code",
    "notes"                    => "Notas",
    "cancelled_at"             => "Fecha de cancelación",
  }.freeze

  # Mapa de valores de enums: "Modelo.atributo" => { valor_db => etiqueta }
  # PaperTrail guarda el valor crudo de la DB (entero). Sin este mapa,
  # los cambios de estado se muestran como "0 → 4" en lugar de
  # "Pendiente de confirmar → Entregada".
  ENUM_VALUE_MAPS = {
    "Delivery.status" => {
      0 => "Pendiente de confirmar",
      1 => "Confirmada para entregar",
      2 => "En plan",
      3 => "En ruta",
      4 => "Entregada",
      5 => "Reprogramada",
      6 => "Cancelada",
      7 => "Archivada",
      8 => "Entrega fracasada",
      9 => "Cargada en camión",
      10 => "En bodegaje"
    },
    "Delivery.delivery_type" => {
      0 => "Entrega normal",
      1 => "Retiro en sala + entrega al cliente",
      2 => "Devolución de producto",
      3 => "Reparación en sitio",
      4 => "Mandado interno",
      5 => "Solo retiro (sin entrega posterior)"
    },
    "Delivery.load_status" => {
      0 => "Sin cargar",
      1 => "Parcialmente cargado",
      2 => "Completamente cargado",
      3 => "Con faltantes"
    },
    "DeliveryItem.status" => {
      0 => "Pendiente de confirmar",
      1 => "Confirmado",
      2 => "En plan de entregas",
      3 => "En ruta",
      4 => "Entregado",
      5 => "Reprogramado",
      6 => "Cancelado",
      7 => "Entrega fracasada",
      8 => "Cargado en camión"
    },
    "DeliveryItem.load_status" => {
      0 => "Sin cargar",
      1 => "Cargado",
      2 => "Faltante"
    },
    "Order.status" => {
      0 => "En producción",
      1 => "Listo para entrega",
      2 => "Entregado",
      3 => "Reprogramado",
      4 => "Cancelado"
    },
    "OrderItem.status" => {
      0 => "En producción",
      1 => "Listo",
      2 => "Entregado",
      3 => "Cancelado",
      4 => "Faltante"
    },
    "DeliveryPlan.status" => {
      0 => "Borrador",
      1 => "Enviado a logística",
      2 => "Ruta creada",
      3 => "En progreso",
      4 => "Completado",
      5 => "Abortado"
    },
    "DeliveryPlan.load_status" => {
      0 => "Sin cargar",
      1 => "Parcialmente cargado",
      2 => "Completamente cargado",
      3 => "Con faltantes"
    },
    "DeliveryPlanAssignment.status" => {
      0 => "Pendiente",
      1 => "En ruta",
      2 => "Completado",
      3 => "Cancelado"
    }
  }.freeze

  CRITICAL_ATTRS = %w[status cancelled_at delivery_date].freeze
  MODERATE_ATTRS = %w[delivery_type load_status confirmed_by_vendor warehousing_until
                      assigned_user_id seller_id delivery_address_id].freeze
  FK_ATTRS = %w[delivery_address_id order_id order_item_id delivery_id seller_id
                client_id assigned_user_id delivery_plan_id].freeze

  # Atributos más importantes a mostrar en el resumen de creación
  CREATE_PRIORITY_KEYS = %w[status delivery_type delivery_date product quantity number name address].freeze

  # ── Cambios ────────────────────────────────────────────────────────────────

  def summarize_changes(version, max_keys: 100)
    changes = version.changeset
    return {} if changes.blank?

    changes.except(*IGNORED_KEYS).first(max_keys).to_h
  rescue StandardError
    {}
  end

  # Campos relevantes para eventos de creación (descarta nulos y FKs secundarias)
  def create_summary(version)
    changes = version.changeset
    return {} if changes.blank?

    all = changes.except(*IGNORED_KEYS).transform_values(&:last)
                 .reject { |_, v| v.nil? || v.to_s.strip.empty? }

    ordered = CREATE_PRIORITY_KEYS.filter_map { |k| [k, all[k]] if all.key?(k) }.to_h
    rest = all.reject { |k, _| CREATE_PRIORITY_KEYS.include?(k) || FK_ATTRS.include?(k) }.first(4).to_h
    ordered.merge(rest)
  rescue StandardError
    {}
  end

  # Campos relevantes para eventos de eliminación (usa el objeto guardado)
  def destroy_summary(version)
    return {} if version.object.blank?

    obj = version.object_deserialized
    return {} unless obj.is_a?(Hash)

    obj.slice(*CREATE_PRIORITY_KEYS).reject { |_, v| v.nil? }.first(5).to_h
  rescue StandardError
    {}
  end

  # Traduce un valor usando el mapa de enums del modelo si corresponde,
  # con fallback a formato genérico legible.
  def format_change_value(value, attr, item_type = nil)
    return "—" if value.nil?
    return "vacío" if value.to_s.strip.empty?

    if item_type.present?
      enum_map = ENUM_VALUE_MAPS["#{item_type}.#{attr}"]
      if enum_map
        int_key = Integer(value) rescue nil
        int_key ||= enum_key_to_int(item_type, attr, value)
        label = enum_map[int_key] || enum_map[value.to_s]
        return label if label
      end
    end

    return "ID: #{value}" if FK_ATTRS.include?(attr.to_s) && value.present?

    format_value_detailed(value)
  end

  # version.changeset expone los enums ya casteados (ej. "confirmed") en
  # eventos create/update, en vez del entero crudo que usa ENUM_VALUE_MAPS.
  # Esto resuelve el entero original para poder traducirlo igual.
  def enum_key_to_int(item_type, attr, value)
    return nil unless value.is_a?(String)

    klass = item_type.constantize
    accessor = attr.to_s.pluralize
    klass.respond_to?(accessor) ? klass.public_send(accessor)[value] : nil
  rescue NameError, ArgumentError
    nil
  end

  def format_value_detailed(value)
    return "—" if value.nil?
    return "vacío" if value.to_s.strip.empty?
    return value.strftime("%d/%m/%Y %H:%M") if value.is_a?(Time) || value.is_a?(DateTime)
    return value.strftime("%d/%m/%Y") if value.is_a?(Date)
    return value ? "Sí" : "No" if value.is_a?(TrueClass) || value.is_a?(FalseClass)

    value.to_s.truncate(200)
  end

  def attribute_label(attr, _item_type = nil)
    ATTRIBUTE_LABELS[attr.to_s] || attr.to_s.humanize
  end

  def change_severity(attr)
    if CRITICAL_ATTRS.include?(attr.to_s) then "danger"
    elsif MODERATE_ATTRS.include?(attr.to_s) then "warning"
    else "secondary"
    end
  end

  # ── Badges / íconos ────────────────────────────────────────────────────────

  def event_badge(event)
    labels = {"create" => "Creado", "update" => "Actualizado", "destroy" => "Eliminado"}
    colors = {"create" => "success", "update" => "primary", "destroy" => "danger"}
    icons  = {"create" => "bi-plus-circle", "update" => "bi-pencil", "destroy" => "bi-trash"}

    label = labels[event] || event.humanize
    color = colors[event] || "secondary"
    icon  = icons[event] || "bi-circle"

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

    if item.respond_to?(:name) && item.name.present?
      "#{version.item_type}: #{item.name}"
    elsif item.respond_to?(:order_number) && item.order_number.present?
      "#{version.item_type}: #{item.order_number}"
    else
      "#{version.item_type} ##{version.item_id}"
    end
  end

  def related_context_description(resource)
    case resource
    when Delivery    then "Ítems de esta entrega"
    when Order       then "Ítems y entregas del pedido"
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
      "Delivery"               => "bi bi-truck",
      "DeliveryItem"           => "bi bi-box-seam",
      "Order"                  => "bi bi-receipt",
      "OrderItem"              => "bi bi-list-ul",
      "DeliveryPlan"           => "bi bi-calendar3",
      "DeliveryPlanAssignment" => "bi bi-calendar-check",
      "User"                   => "bi bi-person",
      "Client"                 => "bi bi-building"
    }
    icons[item_type.to_s] || "bi bi-file-earmark"
  end

  # Etiqueta legible para el registro
  def item_label(version)
    record = safe_find_item(version)

    return "#{version.item_type} ##{version.item_id}" unless record.present?

    case record
    when DeliveryItem
      product = record.order_item&.product
      product.present? ? "#{version.item_type} — #{product}" : "#{version.item_type} ##{version.item_id}"
    when Delivery
      date = record.delivery_date&.strftime("%d/%m/%Y")
      order_num = record.order_number rescue nil
      parts = [date, order_num].compact.join(" · ")
      parts.present? ? "Entrega #{parts}" : "Entrega ##{version.item_id}"
    when Order
      record.number.present? ? "Pedido #{record.number}" : "Pedido ##{version.item_id}"
    when OrderItem
      record.product.present? ? "Ítem — #{record.product}" : "Ítem ##{version.item_id}"
    else
      if record.respond_to?(:name) && record.name.present?
        "#{version.item_type} — #{record.name}"
      else
        "#{version.item_type} ##{version.item_id}"
      end
    end
  end
end

# app/helpers/audit_logs_helper.rb
module AuditLogsHelper
  # ========================================================================
  # 🔹 BADGES Y ETIQUETAS
  # ========================================================================

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
    when "DeliveryPlanAssignment"
      "Asignación de plan ##{id}"
    when "DeliveryAddress"
      "Dirección de entrega ##{id}"
    when "User"
      "Usuario ##{id}"
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

  # 🔹 NUEVO: Descripción contextual de cambios relacionados
  def related_context_description(resource)
    case resource
    when Delivery
      "Cambios en items de esta entrega"
    when Order
      "Cambios en items y entregas de este pedido"
    when DeliveryPlan
      "Cambios en asignaciones de este plan"
    else
      "Cambios en registros relacionados"
    end
  end

  # ========================================================================
  # 🔹 MÉTODO PRINCIPAL: obtener resumen de cambios legibles
  # ========================================================================
  def summarize_changes(version, max_keys: 5)
    raw_changes =
      if version_has_object_changes?(version)
        parse_object_changes_raw(version)
      else
        compute_raw_changes_with_reify(version)
      end

    display_changes = build_display_changes(version, raw_changes)

    display_changes.first(max_keys).to_h
  rescue => e
    Rails.logger.error "Error al procesar cambios en version #{version.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {}
  end

  # ========================================================================
  # 🔹 Detectar si la versión tiene columna + datos en object_changes
  # ========================================================================
  def version_has_object_changes?(version)
    version.has_attribute?(:object_changes) && version.object_changes.present?
  end

  # ========================================================================
  # 🔹 Leer object_changes SIN formatear (valores crudos)
  #     Formato de salida: { "campo" => [before, after], ... }
  # ========================================================================
  def parse_object_changes_raw(version)
    raw = YAML.safe_load(
      version.object_changes,
      permitted_classes: [
        Time, Date, DateTime, ActiveSupport::TimeWithZone,
        Symbol, BigDecimal, ActiveSupport::HashWithIndifferentAccess
      ],
      aliases: true
    ) || {}

    raw.except(*ignored_audit_attributes)
  rescue => e
    Rails.logger.error "Error al parsear object_changes para version #{version.id}: #{e.message}"
    {}
  end

  # ========================================================================
  # 🔹 Calcular cambios usando reify (fallback cuando no hay object_changes)
  #     Formato de salida: { "campo" => [before, after], ... }
  # ========================================================================
  def compute_raw_changes_with_reify(version)
    before_attrs =
      case version.event
      when "create"
        {}
      else
        version.reify&.attributes || {}
      end

    after_attrs =
      case version.event
      when "destroy"
        {}
      else
        state_after(version)
      end

    keys = (before_attrs.keys + after_attrs.keys).uniq - ignored_audit_attributes

    keys.each_with_object({}) do |attr, h|
      before = before_attrs[attr]
      after = after_attrs[attr]
      next if before == after # sin cambio real
      h[attr] = [before, after]
    end
  rescue => e
    Rails.logger.error "Error en compute_raw_changes_with_reify para version #{version.id}: #{e.message}"
    {}
  end

  # ========================================================================
  # 🔹 Atributos que no queremos mostrar jamás en el log
  # ========================================================================
  def ignored_audit_attributes
    %w[id created_at updated_at lock_version]
  end

  # ========================================================================
  # 🔹 Construir hash de cambios listo para mostrar
  #     - Usa reflexión de asociaciones para *_id
  #     - Formatea atributos simples con format_value
  #     Formato de salida: { "Etiqueta bonita" => ["antes", "después"], ... }
  # ========================================================================
  def build_display_changes(version, raw_changes)
    model = version.item_type.safe_constantize

    raw_changes.each_with_object({}) do |(attr, (before, after)), h|
      next if before == after

      attr_str = attr.to_s

      if model && attr_str.end_with?("_id")
        association_name = attr_str.sub(/_id\z/, "").to_sym
        reflection = model.reflect_on_association(association_name)

        label =
          if reflection
            reflection.klass.model_name.human # ej: "Vendedor", "Cliente"
          else
            association_name.to_s.humanize
          end

        before_display = display_value_for_association(reflection, before)
        after_display = display_value_for_association(reflection, after)

        h[label] = [before_display, after_display]

      elsif model && enum_attribute?(model, attr_str)
        # 🔹 CASO ENUM: traducir integer → nombre del enum → etiqueta humana
        label = attr_str.humanize

        before_display = enum_human_value(model, attr_str, before)
        after_display = enum_human_value(model, attr_str, after)

        h[label] = [before_display, after_display]

      else
        label = attr_str.humanize
        h[label] = [format_value(before), format_value(after)]
      end
    end
  end

  # ¿Este atributo es un enum en el modelo?
  def enum_attribute?(model_class, attr_name)
    model_class.defined_enums.key?(attr_name.to_s)
  end

  # Traduce un valor de enum (integer o string) a una etiqueta amigable:
  # - Usa mapping del enum: 0 → "in_route"
  # - Intenta usar métodos display_* del modelo
  # - Si no existen, usa humanize del símbolo
  def enum_human_value(model_class, attr_name, raw_value)
    return "(vacío)" if raw_value.nil? || raw_value == ""

    enum_map = model_class.defined_enums[attr_name.to_s]
    return raw_value.to_s unless enum_map

    # raw_value puede venir como integer (0) o string ("in_route")
    enum_key =
      if raw_value.is_a?(Integer)
        enum_map.key(raw_value) # 0 → "scheduled"
      else
        raw_value.to_s
      end

    return raw_value.to_s unless enum_key

    # Intentar usar métodos de instancia del modelo para mejor label
    instance = safe_dummy_instance(model_class, attr_name, enum_key)

    # Casos especiales según tus modelos
    case model_class.name
    when "Delivery"
      case attr_name.to_s
      when "status"
        return instance.respond_to?(:display_status) ? instance.display_status : enum_key.humanize
      when "delivery_type"
        return instance.respond_to?(:display_type) ? instance.display_type : enum_key.humanize
      when "load_status"
        return instance.respond_to?(:display_load_status) ? instance.display_load_status : enum_key.humanize
      end
    when "DeliveryItem"
      case attr_name.to_s
      when "status"
        return instance.respond_to?(:display_status) ? instance.display_status : enum_key.humanize
      when "load_status"
        return instance.respond_to?(:display_load_status) ? instance.display_load_status : enum_key.humanize
      end
    when "DeliveryPlan"
      case attr_name.to_s
      when "status"
        return instance.respond_to?(:display_status) ? instance.display_status : enum_key.humanize
      when "load_status"
        return instance.respond_to?(:display_load_status) ? instance.display_load_status : enum_key.humanize
      when "truck"
        return instance.respond_to?(:truck_label) ? instance.truck_label : enum_key.humanize
      end
    when "Order"
      return instance.respond_to?(:display_status) ? instance.display_status : enum_key.humanize if attr_name.to_s == "status"
    when "OrderItem"
      return instance.respond_to?(:display_status) ? instance.display_status : enum_key.humanize if attr_name.to_s == "status"
    when "User"
      return instance.respond_to?(:display_role) ? instance.display_role : enum_key.humanize if attr_name.to_s == "role"
    end

    # Fallback genérico
    enum_key.humanize
  rescue => e
    Rails.logger.error "Error en enum_human_value para #{model_class.name}##{attr_name} (#{raw_value}): #{e.message}"
    raw_value.to_s
  end

  # Crea una instancia "dummy" del modelo con solo ese atributo seteado
  # para poder usar display_status, display_type, etc., sin tocar DB.
  def safe_dummy_instance(model_class, attr_name, enum_key)
    model_class.new(attr_name.to_sym => enum_key)
  rescue
    model_class.new
  end

  # ========================================================================
  # 🔹 Mostrar valor de una asociación belongs_to de forma amigable
  # ========================================================================
  def display_value_for_association(reflection, id)
    return "(vacío)" if id.nil? || id == ""

    # Si no sabemos la asociación, devolvemos el ID tal cual
    unless reflection
      return "##{id}"
    end

    record = reflection.klass.find_by(id: id)
    return "##{id}" unless record

    # Heurísticas para nombre legible según tus modelos:
    if record.respond_to?(:name) && record.name.present?
      # Client, Seller, User, etc.
      "#{record.name} (##{record.id})"
    elsif record.respond_to?(:seller_code) && record.seller_code.present?
      # Seller
      "#{record.seller_code} (##{record.id})"
    elsif record.respond_to?(:number) && record.number.present?
      # Order
      "Pedido #{record.number} (##{record.id})"
    elsif record.respond_to?(:address) && record.address.present?
      # DeliveryAddress
      addr_short = record.address.truncate(50)
      "#{addr_short} (##{record.id})"
    elsif record.respond_to?(:full_name) && record.full_name.present?
      # DeliveryPlan
      record.full_name
    elsif record.is_a?(Delivery)
      "Entrega ##{record.id}"
    else
      "#{reflection.klass.model_name.human} ##{record.id}"
    end
  rescue => e
    Rails.logger.error "Error al resolver asociación para #{reflection&.klass} con id=#{id}: #{e.message}"
    "##{id}"
  end

  # ========================================================================
  # 🔹 Estado "después de este cambio" (histórico real)
  # ========================================================================
  def state_after(version)
    return {} if version.event == "destroy"

    next_version = version.next

    obj =
      if next_version
        # Estado del objeto justo antes del siguiente cambio
        next_version.reify
      else
        # Última versión → usamos el registro actual
        version.item
      end

    obj&.attributes || {}
  rescue => e
    Rails.logger.error "Error al obtener state_after para version #{version.id}: #{e.message}"
    {}
  end

  # ========================================================================
  # 🔹 FORMATEO DE VALORES
  # ========================================================================

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

  # ========================================================================
  # 🔹 ICONOS Y COLORES
  # ========================================================================

  # Icono según tipo de recurso
  def resource_icon(item_type)
    icons = {
      "Order" => "bi-cart-check",
      "Delivery" => "bi-truck",
      "DeliveryPlan" => "bi-calendar-week",
      "DeliveryPlanAssignment" => "bi-pin-map",
      "Client" => "bi-person",
      "Seller" => "bi-person-badge",
      "OrderItem" => "bi-box-seam",
      "DeliveryItem" => "bi-box",
      "DeliveryAddress" => "bi-geo-alt",
      "User" => "bi-person-circle"
    }

    icons[item_type] || "bi-file-earmark"
  end

  # Color según tipo de cambio
  def change_severity(attr)
    critical = %w[status approved archived confirmed_by_vendor delivery_date seller_id client_id seller cliente vendedor]
    warning = %w[quantity quantity_delivered delivery_type order_id driver_id conductor]

    attr_lower = attr.to_s.downcase

    return "danger" if critical.any? { |c| attr_lower.include?(c) }
    return "warning" if warning.any? { |w| attr_lower.include?(w) }
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

  # ========================================================================
  # 🔹 MÉTODOS AUXILIARES
  # ========================================================================

  # Atributos que no queremos mostrar
  def skip_attribute?(attr)
    ignored_audit_attributes.include?(attr.to_s)
  end
end

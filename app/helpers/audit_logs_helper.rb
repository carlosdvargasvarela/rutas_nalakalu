module AuditLogsHelper
  # Devuelve un Hash con cambios resumidos y enmascarados
  # version: instancia de PaperTrail::Version
  # max_keys: máximo de atributos a mostrar en resumen
  def summarize_changes(version, max_keys: 5)
    # Si tu PaperTrail guarda object_changes, úsalo; si no, hacemos fallback a object + reify
    changes = fetch_changes_hash(version)

    # Enmascarar datos sensibles
    masked = changes.transform_values do |(before, after)|
      [ mask_value(version.item_type, before), mask_value(version.item_type, after) ]
    end

    # Ordenar por nombre de atributo y limitar
    masked.first(max_keys).to_h
  end

  def fetch_changes_hash(version)
    if version.respond_to?(:object_changes) && version.object_changes.present?
      # object_changes puede venir como texto. PaperTrail lo deserializa a Hash si está configurado.
      oc = version.object_changes
      oc = YAML.safe_load(oc) if oc.is_a?(String)
      # Asegurar formato { attr => [before, after] }
      oc.is_a?(Hash) ? oc : {}
    else
      # Reconstruir diff mínimo entre estado anterior y actual (cuando no hay object_changes)
      before_obj = version.reify # estado antes del cambio (nil si create)
      after_obj  = safe_find_item(version) # estado actual del registro (nil si destroy)
      before_h = before_obj&.attributes || {}
      after_h  = after_obj&.attributes || {}
      # Comparar claves y detectar cambios
      (before_h.keys | after_h.keys).each_with_object({}) do |key, acc|
        b = before_h[key]
        a = after_h[key]
        acc[key] = [ b, a ] if b != a
      end
    end
  rescue => e
    Rails.logger.warn("AuditLogsHelper#fetch_changes_hash error: #{e.class}: #{e.message}")
    {}
  end

  def mask_value(item_type, value)
    return value if value.nil?

    sensitive_attrs = {
      "Delivery" => %w[contact_phone contact_id],
      "Client"   => %w[email phone],
      "User"     => %w[email current_sign_in_ip last_sign_in_ip],
      "Seller"   => %w[],
      "Order"    => %w[]
    }

    # Enmascarar strings que parezcan cédulas/teléfonos/correos si están en attrs sensibles
    if value.is_a?(String)
      if value.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
        return value.gsub(/(^.).+(@)/, '\1***\2').gsub(/\.(.+)$/, ".*")
      end
      if value.gsub(/\D/, "").length >= 8 # número largo probable de teléfono/cédula
        return value[0, 3] + "****" + value[-2, 2].to_s
      end
    end

    value
  end

  def event_badge(event)
    case event
    when "create"
      content_tag(:span, "Creado", class: "badge bg-success")
    when "update"
      content_tag(:span, "Actualizado", class: "badge bg-primary")
    when "destroy"
      content_tag(:span, "Eliminado", class: "badge bg-danger")
    else
      content_tag(:span, event.to_s.humanize, class: "badge bg-secondary")
    end
  end

  def human_model_name(item_type)
    # Si tenés I18n de modelos, podés mapear aquí a algo más agradable
    item_type
  end

  def item_label(version)
    # Texto amigable del recurso (e.g. Order #123)
    base = "#{human_model_name(version.item_type)} ##{version.item_id}"
    if (record = safe_find_item(version))
      if record.respond_to?(:number) && record.number.present?
        return "#{human_model_name(version.item_type)} #{record.number}"
      elsif record.respond_to?(:name) && record.name.present?
        return "#{human_model_name(version.item_type)} #{record.name}"
      elsif record.respond_to?(:delivery_date) && record.delivery_date.present?
        return "#{human_model_name(version.item_type)} #{record.delivery_date}"
      end
    end
    base
  end

  def safe_find_item(version)
    item_klass = version.item_type.safe_constantize
    return nil unless item_klass
    item_klass.find_by(id: version.item_id)
  end

  def format_datetime_cr(dt)
    return "" unless dt
    dt.in_time_zone("America/Costa_Rica").strftime("%d/%m/%Y %H:%M")
  end

  def user_name_for(version, users_by_id)
    user = users_by_id[version.whodunnit.to_s] if version.whodunnit.present?
    user ? user.name : (version.whodunnit.presence || "Sistema")
  end

  def change_arrow
    # Bootstrap Icons chevron-right
    content_tag(:i, "", class: "bi bi-arrow-right")
  end
end

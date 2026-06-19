# app/helpers/timeline_helper.rb
module TimelineHelper
  # ── Dot ────────────────────────────────────────────────────────────────────

  def timeline_icon(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.icon
    else
      event_icon(entry.record.event)
    end
  end

  def timeline_color(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.color
    else
      event_color(entry.record.event)
    end
  end

  # ── Texto ──────────────────────────────────────────────────────────────────

  def timeline_title(entry)
    if entry.delivery_event? || entry.plan_event?
      entry.record.label
    else
      case entry.record.event
      when "create" then "Registro creado"
      when "update" then "Actualización técnica"
      when "destroy" then "Registro eliminado"
      else entry.record.event.humanize
      end
    end
  end

  def timeline_description(entry, users_by_id: {})
    if entry.delivery_event?
      delivery_event_description(entry.record)
    elsif entry.plan_event?
      plan_event_description(entry.record)
    elsif entry.record.event == "create"
      describe_fields(create_summary(entry.record), entry.record.item_type, "Registro creado")
    elsif entry.record.event == "destroy"
      describe_fields(destroy_summary(entry.record), entry.record.item_type, "Registro eliminado")
    else
      changes = summarize_changes(entry.record, max_keys: 5)
      return "Sin cambios detectados" if changes.blank?

      changes.map do |attr, (before, after)|
        "#{attr.humanize}: #{format_value_detailed(before)} → #{format_value_detailed(after)}"
      end.join(" · ")
    end
  end

  def describe_fields(fields, item_type, fallback)
    return fallback if fields.blank?

    fields.map { |attr, value| "#{attribute_label(attr, item_type)}: #{format_change_value(value, attr, item_type)}" }.join(" · ")
  end

  def timeline_actor(entry, users_by_id = {})
    if entry.delivery_event? || entry.plan_event?
      entry.record.actor_name
    else
      user_name_for(entry.record, users_by_id)
    end
  end

  # ── Badges ─────────────────────────────────────────────────────────────────

  def timeline_source_badge(entry)
    if entry.delivery_event? || entry.plan_event?
      content_tag(:span, safe_join([
        content_tag(:i, "", class: "bi bi-activity me-1"),
        "Negocio"
      ]), class: "badge bg-primary-subtle text-primary-emphasis",
        style: "font-size:0.65rem;")
    else
      content_tag(:span, safe_join([
        content_tag(:i, "", class: "bi bi-code-square me-1"),
        "Sistema"
      ]), class: "badge bg-secondary-subtle text-secondary-emphasis",
        style: "font-size:0.65rem;")
    end
  end

  def timeline_context_label(entry, viewing)
    if viewing.is_a?(Delivery) && entry.plan_event?
      plan = entry.record.delivery_plan
      "Plan semana #{plan.week}-#{plan.year}" if plan
    elsif viewing.is_a?(DeliveryPlan) && entry.delivery_event?
      "Entrega ##{entry.record.delivery_id}"
    end
  end

  # ── Highlight crítico ──────────────────────────────────────────────────────

  CRITICAL_ACTIONS = %w[cancelled service_case_created sala_pickup_created].freeze

  def timeline_critical?(entry)
    entry.delivery_event? && CRITICAL_ACTIONS.include?(entry.record.action)
  end

  # ── Helpers de PaperTrail (reutilizados desde AuditLogsHelper) ─────────────

  def event_icon(event)
    case event
    when "create" then "bi-plus-circle-fill"
    when "update" then "bi-pencil-fill"
    when "destroy" then "bi-trash-fill"
    else "bi-circle-fill"
    end
  end

  def event_color(event)
    case event
    when "create" then "success"
    when "update" then "primary"
    when "destroy" then "danger"
    else "secondary"
    end
  end
end

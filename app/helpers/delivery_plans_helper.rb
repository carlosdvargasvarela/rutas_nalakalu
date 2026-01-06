# app/helpers/delivery_plans_helper.rb
module DeliveryPlansHelper
  def week_range_label(year, week, show_year: false)
    return "-" if year.blank? || week.blank? || !week.to_s.match?(/\A\d+\z/) || !year.to_s.match?(/\A\d+\z/)

    year = year.to_i
    week = week.to_i

    first_day = Date.commercial(year, week, 1)
    last_day = Date.commercial(year, week, 7)
    label = "#{l(first_day, format: "%d %b")} - #{l(last_day, format: "%d %b")}"
    show_year ? "#{label} #{year}" : label
  rescue ArgumentError
    "-"
  end

  def grouped_assignments_by_stop(assignments)
    assignments.group_by(&:stop_order).sort_by { |stop, _| stop }
  end

  def stop_badge_class(is_first, group_size)
    if is_first
      "bg-primary"
    else
      "bg-secondary"
    end
  end

  def assignment_status_badge_class(status)
    case status.to_s
    when "delivered"
      "success"
    when "pending"
      "warning"
    when "cancelled"
      "danger"
    else
      "secondary"
    end
  end

  # 🔹 NUEVO: Helper para el color de estado del plan
  def delivery_plan_status_color(status)
    case status.to_s
    when "draft"
      "secondary"
    when "sent_to_logistics"
      "info"
    when "routes_created"
      "primary"
    when "in_progress"
      "warning"
    when "completed"
      "success"
    when "aborted"
      "danger"
    else
      "secondary"
    end
  end

  # 🔹 NUEVO: Helper para el label humanizado del estado
  def delivery_plan_status_label(status)
    case status.to_s
    when "draft"
      "Borrador"
    when "sent_to_logistics"
      "Enviado a logística"
    when "routes_created"
      "Ruta creada"
    when "in_progress"
      "En progreso"
    when "completed"
      "Completado"
    when "aborted"
      "Abortado"
    else
      "Sin estado"
    end
  end

  # 🔹 NUEVO: Helper para el ícono del estado
  def delivery_plan_status_icon(status)
    case status.to_s
    when "draft"
      "bi-file-earmark-text"
    when "sent_to_logistics"
      "bi-send"
    when "routes_created"
      "bi-map"
    when "in_progress"
      "bi-truck"
    when "completed"
      "bi-check-circle-fill"
    when "aborted"
      "bi-x-circle-fill"
    else
      "bi-circle"
    end
  end
end

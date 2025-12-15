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
end

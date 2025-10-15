# app/helpers/delivery_plans_helper.rb
module DeliveryPlansHelper
  def week_range_label(year, week, show_year: false)
    return "-" if year.blank? || week.blank? || !week.to_s.match?(/\A\d+\z/) || !year.to_s.match?(/\A\d+\z/)

    year = year.to_i
    week = week.to_i

    first_day = Date.commercial(year, week, 1)
    last_day  = Date.commercial(year, week, 7)
    label = "#{l(first_day, format: '%d %b')} - #{l(last_day, format: '%d %b')}"
    show_year ? "#{label} #{year}" : label
  rescue ArgumentError
    "-"
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

  def delivery_status_color(status)
    case status.to_s
    when "confirmed", "delivered"
      "success"
    when "pending"
      "warning"
    when "cancelled"
      "danger"
    else
      "secondary"
    end
  end

  def delivery_plan_status_color(status)
    case status.to_s
    when "completed"
      "success"
    when "in_progress"
      "primary"
    when "pending"
      "warning"
    else
      "secondary"
    end
  end
end

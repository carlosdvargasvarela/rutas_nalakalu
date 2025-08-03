# app/helpers/delivery_plans_helper.rb
module DeliveryPlansHelper
  def week_range_label(year, week, show_year: false)
    return "-" if year.blank? || week.blank? || !week.to_s.match?(/\A\d+\z/) || !year.to_s.match?(/\A\d+\z/)

    year = year.to_i
    week = week.to_i + 1

    first_day = Date.commercial(year, week, 1)
    last_day  = Date.commercial(year, week, 7)
    label = "#{l(first_day, format: '%d %b')} - #{l(last_day, format: '%d %b')}"
    show_year ? "#{label} #{year}" : label
  rescue ArgumentError
    "-"
  end
end

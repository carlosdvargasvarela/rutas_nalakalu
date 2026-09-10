# app/helpers/notifications_helper.rb
module NotificationsHelper
  def notification_type_icon(type)
    case type
    when "production_reminder" then "fas fa-industry"
    when "urgent_alert" then "fas fa-exclamation-triangle"
    when "weekly_reminder" then "fas fa-calendar-week"
    when "daily_reminder" then "fas fa-clock"
    when "next_week_pending_confirmation" then "fas fa-clipboard-check"
    when "reschedule_delivery" then "fas fa-calendar-alt"
    when "reschedule_item" then "fas fa-box-open"
    else
      "fas fa-bell"
    end
  end

  def notification_type_color(type)
    case type
    when "production_reminder" then "primary"
    when "urgent_alert" then "danger"
    when "weekly_reminder" then "info"
    when "daily_reminder" then "warning"
    when "next_week_pending_confirmation" then "success"
    when "reschedule_delivery" then "warning"
    when "reschedule_item" then "info"
    else
      "secondary"
    end
  end
end

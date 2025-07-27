# app/helpers/application_helper.rb
module ApplicationHelper
  def delivery_status_color(status)
    case status
    when 'scheduled' then 'primary'
    when 'ready_to_deliver' then 'info'
    when 'in_route' then 'warning'
    when 'delivered' then 'success'
    when 'rescheduled' then 'secondary'
    when 'cancelled' then 'danger'
    else 'secondary'
    end
  end

  def delivery_item_status_color(status)
    case status
    when 'pending' then 'secondary'
    when 'confirmed' then 'primary'
    when 'in_route' then 'warning'
    when 'delivered' then 'success'
    when 'rescheduled' then 'info'
    when 'cancelled' then 'danger'
    when 'service_case' then 'warning'
    else 'secondary'
    end
  end
end
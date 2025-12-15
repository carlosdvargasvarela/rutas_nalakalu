# app/services/delivery_reschedule_service.rb
class DeliveryRescheduleService
  def initialize(delivery, new_date)
    @delivery = delivery
    @new_date = new_date
  end

  def reschedule!
    @delivery.update!(delivery_date: @new_date, status: :rescheduled)
    @delivery.delivery_items.update_all(status: :rescheduled)
  end
end

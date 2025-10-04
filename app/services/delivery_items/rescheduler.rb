# app/services/delivery_items/rescheduler.rb
module DeliveryItems
  class Rescheduler
    def initialize(delivery_item:, params:, current_user:)
      @delivery_item = delivery_item
      @params = params
      @current_user = current_user
    end

    def call
      validate_can_reschedule!

      if params[:new_delivery] == "true"
        reschedule_to_new_delivery
      elsif params[:target_delivery_id].present?
        reschedule_to_existing_delivery
      else
        raise StandardError, "Debes seleccionar una opción de reagendado."
      end
      update_delivery_status(delivery_item.delivery)

      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::Rescheduler: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :params, :current_user

    def validate_can_reschedule!
      if delivery_item.rescheduled?
        raise StandardError, "No se puede reagendar un producto ya reagendado."
      end
    end

    def reschedule_to_new_delivery
      new_date = params[:new_date].presence && Date.parse(params[:new_date])
      validate_seller_day_restriction!(new_date) if new_date

      delivery_item.reschedule!(new_date: new_date)
    end

    def reschedule_to_existing_delivery
      target_delivery = Delivery.find(params[:target_delivery_id])
      validate_seller_day_restriction!(target_delivery.delivery_date)

      delivery_item.reschedule!(target_delivery: target_delivery)
    end

    def validate_seller_day_restriction!(target_date)
      return unless current_user.role == "seller"

      unless target_date.wday == Date.today.wday
        raise StandardError, "Los vendedores solo pueden reagendar para #{Date::DAYNAMES[Date.today.wday].downcase}s"
      end
    end

    def update_delivery_status(delivery)
      delivery.update_status_based_on_items
    end
  end
end

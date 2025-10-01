# app/services/delivery_items/status_updater.rb
module DeliveryItems
  class StatusUpdater
    def initialize(delivery_item:, new_status:, current_user:)
      @delivery_item = delivery_item
      @new_status = new_status.to_sym
      @current_user = current_user
    end

    def call
      validate_can_update!

      case new_status
      when :confirmed
        delivery_item.update!(status: :confirmed)
        delivery_item.update_delivery_status
      when :delivered
        delivery_item.mark_as_delivered!
      when :cancelled
        delivery_item.update!(status: :cancelled)
        delivery_item.update_delivery_status
      else
        raise ArgumentError, "Estado no válido: #{new_status}"
      end

      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::StatusUpdater: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :new_status, :current_user

    def validate_can_update!
      if delivery_item.rescheduled?
        raise StandardError, "No se puede modificar un producto reagendado."
      end
    end
  end
end
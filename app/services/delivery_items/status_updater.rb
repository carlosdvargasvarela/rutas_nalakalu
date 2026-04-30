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
        record_event("item_confirmed")
      when :delivered
        delivery_item.mark_as_delivered!
        record_event("item_delivered")
      when :cancelled
        delivery_item.update!(status: :cancelled)
        record_event("item_cancelled")
      else
        raise ArgumentError, "Estado no válido: #{new_status}"
      end

      update_delivery_status(delivery_item.delivery)
      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::StatusUpdater: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :new_status, :current_user

    def validate_can_update!
      raise StandardError, "No se puede modificar un producto reagendado." if delivery_item.rescheduled?
    end

    def update_delivery_status(delivery)
      delivery.update_status_based_on_items
    end

    def record_event(action)
      DeliveryEvent.record(
        delivery: delivery_item.delivery,
        action: action,
        actor: current_user,
        payload: {
          delivery_item_id: delivery_item.id,
          product: delivery_item.order_item&.product,
          quantity: delivery_item.quantity_delivered,
          previous_status: delivery_item.status_before_last_save || delivery_item.status
        }
      )
    end
  end
end

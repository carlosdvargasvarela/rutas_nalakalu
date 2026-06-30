module Deliveries
  class Rescheduler
    def initialize(delivery:, new_date:, current_user:, reason: nil)
      @delivery = delivery
      @new_date = new_date
      @current_user = current_user
      @reason = reason
    end

    def call
      validate_new_date!
      validate_can_reschedule!

      old_date = delivery.delivery_date
      old_status = delivery.status.to_sym

      ActiveRecord::Base.transaction do
        @target_delivery = find_or_create_target_delivery
        migrate_items_to_target
        delivery.reload.update_status_based_on_items
        target_delivery.reload.update_status_based_on_items

        # 🔹 Registrar evento en la entrega original
        DeliveryEvent.record(
          delivery: delivery,
          action: "rescheduled",
          actor: current_user,
          payload: {
            target_delivery_id: target_delivery.id,
            reason: reason,
            new_date: target_delivery.delivery_date.to_s,
            old_date: old_date.to_s,
            items_count: delivery.delivery_items.where(status: :rescheduled).count
          }
        )

        # 🔹 Registrar evento en la nueva entrega
        DeliveryEvent.record(
          delivery: target_delivery,
          action: "created",
          actor: current_user,
          payload: {
            source_delivery_id: delivery.id,
            context: "reschedule",
            old_date: old_date.to_s
          }
        )
      end

      notify_users(old_date, old_status)
      notify_current_week_if_needed(old_date)

      target_delivery
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::Rescheduler: #{e.message}")
      raise
    end

    private

    attr_reader :delivery, :new_date, :current_user, :reason, :target_delivery

    def validate_new_date!
      raise ArgumentError, "Debes seleccionar una nueva fecha" if new_date.blank?
      raise ArgumentError, "La nueva fecha debe ser diferente a la original" if new_date == delivery.delivery_date
    end

    def validate_can_reschedule!
      if delivery.delivery_items.exists?(status: :in_route)
        raise StandardError, "No se puede reagendar una entrega con productos en ruta."
      end
    end

    def find_or_create_target_delivery
      active = Delivery.where(
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        delivery_date: new_date
      ).where.not(status: %i[rescheduled cancelled archived delivered]).first

      return active if active.present?

      rescheduled = Delivery.find_by(
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        delivery_date: new_date,
        status: :rescheduled
      )

      if rescheduled.present?
        rescheduled.update_column(:status, Delivery.statuses[:scheduled])
        return rescheduled
      end

      Delivery.create!(
        order: delivery.order,
        delivery_address: delivery.delivery_address,
        delivery_date: new_date,
        contact_name: delivery.contact_name,
        contact_phone: delivery.contact_phone,
        contact_id: delivery.contact_id,
        delivery_type: delivery.delivery_type,
        delivery_notes: delivery.delivery_notes,
        delivery_time_preference: delivery.delivery_time_preference,
        condominio_number: delivery.condominio_number,
        casa_number: delivery.casa_number,
        status: :scheduled
      )
    end

    def migrate_items_to_target
      items_to_migrate = delivery.delivery_items.where(status: %i[pending confirmed in_plan])

      items_to_migrate.find_each do |item|
        existing = target_delivery.delivery_items.find_by(order_item_id: item.order_item_id)

        if existing.present?
          if existing.status.in?(%w[pending confirmed in_plan])
            existing.update!(
              quantity_delivered: existing.quantity_delivered.to_i + item.quantity_delivered.to_i,
              notes: [existing.notes, item.notes].compact_blank.join(" | ")
            )
          elsif existing.rescheduled?
            existing.update!(
              status: target_delivery.default_item_status,
              quantity_delivered: item.quantity_delivered.to_i,
              notes: [existing.notes, item.notes].compact_blank.join(" | ")
            )
          else
            create_item_in_target(item)
          end
        else
          create_item_in_target(item)
        end

        item.update_column(:status, DeliveryItem.statuses[:rescheduled])
      end
    end

    def create_item_in_target(item)
      DeliveryItem.create!(
        delivery: target_delivery,
        order_item: item.order_item,
        quantity_delivered: item.quantity_delivered.to_i,
        status: target_delivery.default_item_status,
        service_case: item.service_case,
        notes: item.notes
      )
    end

    def notify_users(old_date, old_status)
      NotificationService.notify_delivery_rescheduled(
        target_delivery,
        old_date: old_date,
        rescheduled_by: current_user.name,
        reason: reason
      )
    rescue => e
      Rails.logger.error("⚠️ Notificación fallida en Deliveries::Rescheduler: #{e.message}")
    end

    def notify_current_week_if_needed(old_date)
      old_in_current = old_date.cweek == Date.current.cweek && old_date.cwyear == Date.current.cwyear
      new_in_current = new_date.cweek == Date.current.cweek && new_date.cwyear == Date.current.cwyear
      return unless old_in_current || new_in_current

      NotificationService.notify_current_week_delivery_rescheduled(
        target_delivery,
        old_date: old_date,
        rescheduled_by: current_user.name,
        reason: reason
      )
    rescue => e
      Rails.logger.error("⚠️ Notificación semana actual fallida: #{e.message}")
    end
  end
end

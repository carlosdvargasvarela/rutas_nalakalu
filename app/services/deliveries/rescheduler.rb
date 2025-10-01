# app/services/deliveries/rescheduler.rb
module Deliveries
  class Rescheduler
    def initialize(delivery:, new_date:, current_user:)
      @delivery = delivery
      @new_date = new_date
      @current_user = current_user
    end

    def call
      validate_new_date!

      old_date   = delivery.delivery_date
      old_status = delivery.status.to_sym
      @new_delivery = nil

      ActiveRecord::Base.transaction do
        clone_delivery(old_status)
        clear_associations
        migrate_items
        mark_original_as_rescheduled
      end

      notify_users(old_date, old_status)

      new_delivery
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::Rescheduler: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery, :new_date, :current_user, :new_delivery

    def validate_new_date!
      raise ArgumentError, "Debes seleccionar una nueva fecha" if new_date.blank?
      raise ArgumentError, "La nueva fecha debe ser diferente a la original" if new_date == delivery.delivery_date
    end

    def clone_delivery(old_status)
      @new_delivery = delivery.dup
      @new_delivery.delivery_date = new_date
      @new_delivery.status = (old_status == :in_plan ? :scheduled : old_status)
      @new_delivery.save!
    end

    def clear_associations
      new_delivery.delivery_items.destroy_all
      new_delivery.delivery_plan_assignments.destroy_all
      new_delivery.delivery_items.reset
      new_delivery.delivery_plan_assignments.reset
    end

    def migrate_items
      items_to_reschedule = delivery.delivery_items.where.not(status: %i[delivered cancelled rescheduled])
      items_to_reschedule.find_each do |item|
        DeliveryItem.create!(
          delivery: new_delivery,
          order_item: item.order_item,
          quantity_delivered: item.quantity_delivered,
          status: :pending,
          service_case: item.service_case,
          notes: item.notes
        )
        item.update!(status: :rescheduled)
      end
    end

    def mark_original_as_rescheduled
      delivery.update!(status: :rescheduled)
    end

    def notify_users(old_date, old_status)
      users = User.where(role: %i[admin seller production_manager])
      formatted_old = I18n.l old_date, format: :long
      formatted_new = I18n.l new_delivery.delivery_date, format: :long
      message = "La entrega del pedido #{delivery.order.number} con fecha original #{formatted_old} fue reagendada para #{formatted_new}."

      NotificationService.create_for_users(users, new_delivery, message, type: "reschedule_delivery")
    rescue => e
      Rails.logger.error("⚠️ Notificación fallida en Deliveries::Rescheduler: #{e.message}")
    end
  end
end
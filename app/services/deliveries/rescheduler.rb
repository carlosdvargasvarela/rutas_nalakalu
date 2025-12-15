# app/services/deliveries/rescheduler.rb
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
        # 1. Buscar o crear la entrega destino (reutiliza rescheduled si existe)
        @target_delivery = find_or_create_target_delivery

        # 2. Migrar items elegibles a la entrega destino
        migrate_items_to_target

        # 3. Limpiar assignments del delivery original si quedó vacío o sin items activos
        cleanup_original_delivery_assignments

        # 4. Recalcular estados de ambas entregas
        delivery.reload.update_status_based_on_items
        target_delivery.reload.update_status_based_on_items
      end

      # 5. Notificaciones
      notify_users(old_date, old_status)
      notify_current_week_if_needed(old_date)

      target_delivery
    rescue => e
      Rails.logger.error("❌ Error en Deliveries::Rescheduler: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery, :new_date, :current_user, :reason, :target_delivery

    # ============================================================================
    # VALIDACIONES
    # ============================================================================

    def validate_new_date!
      raise ArgumentError, "Debes seleccionar una nueva fecha" if new_date.blank?
      raise ArgumentError, "La nueva fecha debe ser diferente a la original" if new_date == delivery.delivery_date
    end

    def validate_can_reschedule!
      # No permitir reagendar si hay items en ruta (deben completarse o fallar primero)
      if delivery.delivery_items.exists?(status: :in_route)
        raise StandardError, "No se puede reagendar una entrega con productos en ruta. Completa o marca como fallida primero."
      end
    end

    # ============================================================================
    # BUSCAR O CREAR ENTREGA DESTINO (REUTILIZA RESCHEDULED)
    # ============================================================================

    def find_or_create_target_delivery
      # 1. Buscar entrega activa (no terminal) con la misma combinación
      active_delivery = Delivery.where(
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        delivery_date: new_date
      ).where.not(status: [:rescheduled, :cancelled, :archived, :delivered]).first

      return active_delivery if active_delivery.present?

      # 2. Buscar entrega rescheduled y "revivirla"
      rescheduled_delivery = Delivery.find_by(
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        delivery_date: new_date,
        status: :rescheduled
      )

      if rescheduled_delivery.present?
        # Revivir: cambiar a scheduled para que vuelva a ser usable
        rescheduled_delivery.update_column(:status, Delivery.statuses[:scheduled])
        return rescheduled_delivery
      end

      # 3. Si no existe ninguna, crear una nueva
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
        status: :scheduled
      )
    end

    # ============================================================================
    # MIGRACIÓN DE ITEMS
    # ============================================================================

    def migrate_items_to_target
      # Items migrables: vivos en el ORIGEN (pending, confirmed, in_plan). NO in_route ni terminales.
      items_to_migrate = delivery.delivery_items.where(status: [:pending, :confirmed, :in_plan])

      items_to_migrate.find_each do |item|
        # Buscar item destino del mismo order_item
        existing_item = target_delivery.delivery_items.find_by(order_item_id: item.order_item_id)

        if existing_item.present?
          if existing_item.status.in?(%w[pending confirmed in_plan])
            # Consolidar SOLO si el existente está "vivo"
            existing_qty = existing_item.quantity_delivered.to_i
            moving_qty = item.quantity_delivered.to_i

            existing_item.update!(
              quantity_delivered: existing_qty + moving_qty,
              notes: [existing_item.notes, item.notes].compact_blank.join(" | ")
            )
          elsif existing_item.rescheduled?
            # Si el existente está rescheduled, NO sumar su cantidad.
            # Revivirlo y reemplazar su cantidad con la del item que estamos moviendo.
            existing_item.update!(
              status: :pending,
              quantity_delivered: item.quantity_delivered.to_i,
              notes: [existing_item.notes, item.notes].compact_blank.join(" | ")
            )
          else
            # Si es terminal (delivered/cancelled/failed) no sumamos nunca.
            # Creamos un NUEVO item en destino para no tocar históricos.
            DeliveryItem.create!(
              delivery: target_delivery,
              order_item: item.order_item,
              quantity_delivered: item.quantity_delivered.to_i,
              status: :pending,
              service_case: item.service_case,
              notes: item.notes
            )
          end
        else
          # No existe en destino: crear uno nuevo "vivo"
          DeliveryItem.create!(
            delivery: target_delivery,
            order_item: item.order_item,
            quantity_delivered: item.quantity_delivered.to_i,
            status: :pending,
            service_case: item.service_case,
            notes: item.notes
          )
        end

        # Marcar el original como rescheduled
        item.update_column(:status, DeliveryItem.statuses[:rescheduled])
      end
    end

    # ============================================================================
    # LIMPIEZA DE ASSIGNMENTS Y PLANES
    # ============================================================================

    def cleanup_original_delivery_assignments
      # Si el delivery original no tiene items activos (todos rescheduled/cancelled/delivered),
      # remover sus assignments de planes
      active_items = delivery.delivery_items.where.not(status: [:delivered, :cancelled, :rescheduled])

      if active_items.empty?
        # Remover assignments
        delivery.delivery_plan_assignments.destroy_all

        # Marcar el delivery como rescheduled si todos sus items fueron movidos
        all_rescheduled = delivery.delivery_items.all? { |di| di.status.in?(%w[rescheduled cancelled delivered]) }
        delivery.update_column(:status, Delivery.statuses[:rescheduled]) if all_rescheduled
      end
    end

    # ============================================================================
    # NOTIFICACIONES
    # ============================================================================

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
      # Si la nueva fecha cae en la semana ISO actual, notificar extra
      if new_date.cweek == Date.current.cweek && new_date.cwyear == Date.current.cwyear
        NotificationService.notify_current_week_delivery_rescheduled(
          target_delivery,
          old_date: old_date,
          rescheduled_by: current_user.name,
          reason: reason
        )
      end
    rescue => e
      Rails.logger.error("⚠️ Notificación semana actual fallida: #{e.message}")
    end
  end
end

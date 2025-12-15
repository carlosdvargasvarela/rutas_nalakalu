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

      @original_delivery = delivery_item.delivery

      ActiveRecord::Base.transaction do
        if params[:new_delivery] == "true"
          reschedule_to_new_delivery
        elsif params[:target_delivery_id].present?
          reschedule_to_existing_delivery
        else
          raise StandardError, "Debes seleccionar una opción de reagendado."
        end

        # Marcar el item original como rescheduled
        delivery_item.update_column(:status, DeliveryItem.statuses[:rescheduled])

        # Recalcular estados de ambas entregas
        original_delivery.reload.update_status_based_on_items
        target_delivery.reload.update_status_based_on_items

        # Limpiar assignments del delivery original si quedó vacío
        cleanup_original_delivery_if_empty
      end

      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::Rescheduler: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :params, :current_user, :original_delivery, :target_delivery

    # ============================================================================
    # VALIDACIONES
    # ============================================================================

    def validate_can_reschedule!
      if delivery_item.rescheduled?
        raise StandardError, "No se puede reagendar un producto ya reagendado."
      end

      if delivery_item.in_route?
        raise StandardError, "No se puede reagendar un producto en ruta. Completa o marca como fallido primero."
      end
    end

    # ============================================================================
    # REAGENDAR A NUEVA ENTREGA (POR FECHA)
    # ============================================================================

    def reschedule_to_new_delivery
      new_date = parse_new_date

      # Buscar o crear entrega destino con la misma combinación (reutiliza rescheduled)
      @target_delivery = find_or_create_target_delivery(new_date)

      # Mover el item al destino
      move_item_to_target
    end

    # ============================================================================
    # REAGENDAR A ENTREGA EXISTENTE (POR ID)
    # ============================================================================

    def reschedule_to_existing_delivery
      @target_delivery = Delivery.find(params[:target_delivery_id])

      # Validar que pertenece al mismo pedido y dirección
      validate_target_delivery_compatibility!

      # Mover el item al destino
      move_item_to_target
    end

    # ============================================================================
    # HELPERS
    # ============================================================================

    def parse_new_date
      date_str = params[:new_date].presence
      raise ArgumentError, "Debes especificar una fecha" if date_str.blank?

      Date.parse(date_str)
    rescue ArgumentError
      raise ArgumentError, "Fecha inválida"
    end

    def find_or_create_target_delivery(new_date)
      # 1. Buscar entrega activa (no terminal)
      active_delivery = Delivery.where(
        order_id: original_delivery.order_id,
        delivery_address_id: original_delivery.delivery_address_id,
        delivery_date: new_date
      ).where.not(status: [:rescheduled, :cancelled, :archived, :delivered]).first

      return active_delivery if active_delivery.present?

      # 2. Buscar entrega rescheduled y revivirla
      rescheduled_delivery = Delivery.find_by(
        order_id: original_delivery.order_id,
        delivery_address_id: original_delivery.delivery_address_id,
        delivery_date: new_date,
        status: :rescheduled
      )

      if rescheduled_delivery.present?
        rescheduled_delivery.update_column(:status, Delivery.statuses[:scheduled])
        return rescheduled_delivery
      end

      # 3. Si no existe, crear nueva
      Delivery.create!(
        order: original_delivery.order,
        delivery_address: original_delivery.delivery_address,
        delivery_date: new_date,
        contact_name: original_delivery.contact_name,
        contact_phone: original_delivery.contact_phone,
        contact_id: original_delivery.contact_id,
        delivery_type: original_delivery.delivery_type,
        status: :scheduled
      )
    end

    def move_item_to_target
      existing_item = target_delivery.delivery_items.find_by(order_item_id: delivery_item.order_item_id)

      if existing_item.present?
        if existing_item.status.in?(%w[pending confirmed in_plan])
          # Consolidar SOLO si el existente está "vivo"
          existing_qty = existing_item.quantity_delivered.to_i
          moving_qty = delivery_item.quantity_delivered.to_i

          existing_item.update!(
            quantity_delivered: existing_qty + moving_qty,
            notes: [existing_item.notes, delivery_item.notes].compact_blank.join(" | ")
          )
        elsif existing_item.rescheduled?
          # Revivir y reemplazar cantidad (no sumar rescheduled)
          existing_item.update!(
            status: :pending,
            quantity_delivered: delivery_item.quantity_delivered.to_i,
            notes: [existing_item.notes, delivery_item.notes].compact_blank.join(" | ")
          )
        else
          # Terminal: crear un nuevo item sin tocar el histórico
          DeliveryItem.create!(
            delivery: target_delivery,
            order_item: delivery_item.order_item,
            quantity_delivered: delivery_item.quantity_delivered.to_i,
            status: :pending,
            service_case: delivery_item.service_case,
            notes: delivery_item.notes
          )
        end
      else
        DeliveryItem.create!(
          delivery: target_delivery,
          order_item: delivery_item.order_item,
          quantity_delivered: delivery_item.quantity_delivered.to_i,
          status: :pending,
          service_case: delivery_item.service_case,
          notes: delivery_item.notes
        )
      end
    end

    def validate_target_delivery_compatibility!
      unless target_delivery.order_id == original_delivery.order_id &&
          target_delivery.delivery_address_id == original_delivery.delivery_address_id
        raise StandardError, "La entrega destino debe pertenecer al mismo pedido y dirección."
      end
    end

    def cleanup_original_delivery_if_empty
      # Si el delivery original no tiene items activos, remover assignments y marcar como rescheduled
      active_items = original_delivery.delivery_items.where.not(status: [:delivered, :cancelled, :rescheduled])

      if active_items.empty?
        original_delivery.delivery_plan_assignments.destroy_all

        all_rescheduled = original_delivery.delivery_items.all? { |di| di.status.in?(%w[rescheduled cancelled delivered]) }
        original_delivery.update_column(:status, Delivery.statuses[:rescheduled]) if all_rescheduled
      end
    end
  end
end

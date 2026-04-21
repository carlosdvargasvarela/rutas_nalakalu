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
      @quantity_to_reschedule = resolve_quantity

      # FIX: envolver todo con PaperTrail.request para evitar que
      # los callbacks after_commit intenten resolver whodunnit vía Warden
      PaperTrail.request(whodunnit: current_user.id.to_s) do
        ActiveRecord::Base.transaction do
          if params[:new_delivery] == "true"
            reschedule_to_new_delivery
          elsif params[:target_delivery_id].present?
            reschedule_to_existing_delivery
          else
            raise StandardError, "Debes seleccionar una opción de reagendado."
          end

          apply_origin_changes
          original_delivery.reload.update_status_based_on_items
          target_delivery.reload.update_status_based_on_items
          cleanup_original_delivery_if_empty
        end
      end

      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::Rescheduler: #{e.message}")
      raise e
    end

    private

    attr_reader :delivery_item, :params, :current_user,
      :original_delivery, :target_delivery, :quantity_to_reschedule

    def resolve_quantity
      qty = params[:quantity_to_reschedule].to_i
      total = delivery_item.quantity_delivered.to_i

      return total if qty <= 0

      if qty > total
        raise ArgumentError, "No podés reagendar más de #{total} unidades (solicitado: #{qty})."
      end

      qty
    end

    def partial?
      quantity_to_reschedule < delivery_item.quantity_delivered.to_i
    end

    def validate_can_reschedule!
      if delivery_item.rescheduled?
        raise StandardError, "No se puede reagendar un producto ya reagendado."
      end

      if delivery_item.in_route?
        raise StandardError, "No se puede reagendar un producto en ruta. Completa o marca como fallido primero."
      end

      if delivery_item.delivered?
        raise StandardError, "No se puede reagendar un producto ya entregado."
      end
    end

    def reschedule_to_new_delivery
      new_date = parse_new_date

      if new_date == original_delivery.delivery_date
        raise StandardError, "La nueva fecha no puede ser igual a la actual."
      end

      @target_delivery = find_or_create_target_delivery(new_date)
      move_quantity_to_target
    end

    def reschedule_to_existing_delivery
      @target_delivery = Delivery.find(params[:target_delivery_id])

      if target_delivery.id == original_delivery.id
        raise StandardError, "No podés reagendar a la misma entrega."
      end

      validate_target_delivery_compatibility!
      move_quantity_to_target
    end

    def apply_origin_changes
      if partial?
        remaining = delivery_item.quantity_delivered.to_i - quantity_to_reschedule
        delivery_item.update!(quantity_delivered: remaining)
      else
        delivery_item.update_column(:status, DeliveryItem.statuses[:rescheduled])
      end
    end

    def move_quantity_to_target
      existing_item = target_delivery.delivery_items.find_by(order_item_id: delivery_item.order_item_id)

      if existing_item.present?
        # CASO 1: item "vivo" en el destino → sumar (ej: ya había 1 unidad confirmada y agregamos 1 más)
        if existing_item.status.in?(%w[pending confirmed in_plan])
          existing_item.update!(
            quantity_delivered: existing_item.quantity_delivered.to_i + quantity_to_reschedule,
            notes: [existing_item.notes, delivery_item.notes].compact_blank.join(" | ")
          )

        # CASO 2: item "muerto" en el destino → REEMPLAZAR, no sumar
        # Esto cubre el re-reagendamiento: el item viejo quedó como rescheduled/cancelled/failed
        # y ahora volvemos a moverle productos → la cantidad correcta es la que viene, no la suma
        elsif existing_item.status.in?(%w[rescheduled cancelled failed])
          existing_item.update!(
            status: :pending,
            quantity_delivered: quantity_to_reschedule,
            notes: delivery_item.notes
          )

        else
          create_item_in_target
        end
      else
        create_item_in_target
      end
    end

    def create_item_in_target
      DeliveryItem.create!(
        delivery: target_delivery,
        order_item: delivery_item.order_item,
        quantity_delivered: quantity_to_reschedule,
        status: :pending,
        service_case: delivery_item.service_case,
        notes: delivery_item.notes
      )
    end

    def parse_new_date
      date_str = params[:new_date].presence
      raise ArgumentError, "Debes especificar una fecha" if date_str.blank?
      Date.parse(date_str)
    rescue ArgumentError
      raise ArgumentError, "Fecha inválida"
    end

    def find_or_create_target_delivery(new_date)
      active = Delivery.where(
        order_id: original_delivery.order_id,
        delivery_address_id: original_delivery.delivery_address_id,
        delivery_date: new_date
      ).where.not(status: %i[rescheduled cancelled archived delivered]).first

      return active if active.present?

      rescheduled = Delivery.find_by(
        order_id: original_delivery.order_id,
        delivery_address_id: original_delivery.delivery_address_id,
        delivery_date: new_date,
        status: :rescheduled
      )

      if rescheduled.present?
        rescheduled.update_column(:status, Delivery.statuses[:scheduled])
        return rescheduled
      end

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

    def validate_target_delivery_compatibility!
      unless target_delivery.order_id == original_delivery.order_id &&
          target_delivery.delivery_address_id == original_delivery.delivery_address_id
        raise StandardError, "La entrega destino debe pertenecer al mismo pedido y dirección."
      end
    end

    def cleanup_original_delivery_if_empty
      active_items = original_delivery.delivery_items.where.not(status: %i[delivered cancelled rescheduled])
      return unless active_items.empty?

      original_delivery.delivery_plan_assignment&.destroy

      all_terminal = original_delivery.delivery_items.reload.all? do |di|
        di.status.in?(%w[rescheduled cancelled delivered])
      end
      original_delivery.update_column(:status, Delivery.statuses[:rescheduled]) if all_terminal
    end
  end
end

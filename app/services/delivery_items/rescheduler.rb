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
          finalize_original_if_all_terminal
        end
      end

      delivery_item
    rescue => e
      Rails.logger.error("❌ Error en DeliveryItems::Rescheduler: #{e.message}")
      raise
    end

    private

    attr_reader :delivery_item, :params, :current_user,
      :original_delivery, :target_delivery, :quantity_to_reschedule

    def resolve_quantity
      qty = params[:quantity_to_reschedule].to_i
      total = delivery_item.quantity_delivered.to_i
      return total if qty <= 0
      raise ArgumentError, "No podés reagendar más de #{total} unidades (solicitado: #{qty})." if qty > total
      qty
    end

    def partial?
      quantity_to_reschedule < delivery_item.quantity_delivered.to_i
    end

    def validate_can_reschedule!
      raise StandardError, "No se puede reagendar un producto ya reagendado." if delivery_item.rescheduled?
      raise StandardError, "No se puede reagendar un producto en ruta." if delivery_item.in_route?
      raise StandardError, "No se puede reagendar un producto ya entregado." if delivery_item.delivered?
    end

    def reschedule_to_new_delivery
      new_date = parse_new_date
      raise StandardError, "La nueva fecha no puede ser igual a la actual." if new_date == original_delivery.delivery_date
      @target_delivery = find_or_create_target_delivery(new_date)
      move_quantity_to_target
    end

    def reschedule_to_existing_delivery
      @target_delivery = Delivery.find(params[:target_delivery_id])
      raise StandardError, "No podés reagendar a la misma entrega." if target_delivery.id == original_delivery.id
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
      existing = target_delivery.delivery_items.find_by(order_item_id: delivery_item.order_item_id)

      if existing.present?
        if existing.status.in?(%w[pending confirmed in_plan])
          existing.update!(
            quantity_delivered: existing.quantity_delivered.to_i + quantity_to_reschedule,
            notes: [existing.notes, delivery_item.notes].compact_blank.join(" | ")
          )
        elsif existing.status.in?(%w[rescheduled cancelled failed])
          existing.update!(
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

    def finalize_original_if_all_terminal
      all_terminal = original_delivery.delivery_items.reload.all? do |di|
        di.status.in?(%w[rescheduled cancelled delivered failed])
      end

      if all_terminal
        original_delivery.update_column(:status, Delivery.statuses[:rescheduled])
      end
    end
  end
end

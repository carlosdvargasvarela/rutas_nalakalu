# Vuelve a enviar una entrega ya entregada o cancelada: crea una entrega
# nueva con los mismos datos y productos para otra fecha. La original queda
# intacta, así se puede repetir las veces que haga falta (p. ej. flotillas).
module Deliveries
  class Resender
    RESENDABLE_ITEM_STATUSES = %i[delivered cancelled failed].freeze

    # item_ids: productos elegidos; nil = todos los reenviables.
    def initialize(delivery:, new_date:, current_user:, reason: nil, item_ids: nil)
      @item_ids = item_ids
      @delivery = delivery
      @new_date = new_date
      @current_user = current_user
      @reason = reason
    end

    def call
      raise ArgumentError, "Debes seleccionar una fecha" if @new_date.blank?
      raise ArgumentError, "Solo se pueden volver a enviar entregas entregadas o canceladas" unless @delivery.delivered? || @delivery.cancelled?

      items = @delivery.delivery_items.where(status: RESENDABLE_ITEM_STATUSES)
      items = items.where(id: @item_ids) unless @item_ids.nil?
      raise ArgumentError, "Selecciona al menos un producto para volver a enviar" if items.none?

      ActiveRecord::Base.transaction do
        target = Delivery.create!(
          @delivery.attributes.slice(*%w[order_id delivery_address_id contact_name contact_phone contact_id
            delivery_type delivery_notes delivery_time_preference condominio_number casa_number])
            .merge(delivery_date: @new_date, status: :scheduled)
        )

        items.each do |item|
          target.delivery_items.create!(
            order_item: item.order_item,
            quantity_delivered: item.quantity_delivered.to_i,
            status: target.default_item_status,
            service_case: item.service_case,
            notes: item.notes
          )
          # Reabre el pedido/producto (estaba entregado o cancelado).
          item.order_item.update_status_based_on_deliveries
        end

        payload = {reason: @reason, old_date: @delivery.delivery_date.to_s, new_date: @new_date.to_s}
        DeliveryEvent.record(delivery: @delivery, action: "resent", actor: @current_user,
          payload: payload.merge(target_delivery_id: target.id))
        DeliveryEvent.record(delivery: target, action: "created", actor: @current_user,
          payload: payload.merge(source_delivery_id: @delivery.id, context: "resend", delivery_date: @new_date.to_s))
        target
      end
    end
  end
end

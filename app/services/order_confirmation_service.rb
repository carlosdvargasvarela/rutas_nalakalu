# app/services/order_confirmation_service.rb
class OrderConfirmationService
  def initialize(order)
    @order = order
  end

  def confirm_delivery(delivery_params)
    delivery = @order.deliveries.build(delivery_params)

    if delivery.save
      # Crear delivery_items para todos los order_items listos
      @order.order_items.ready.each do |order_item|
        delivery.delivery_items.create!(
          order_item: order_item,
          quantity_delivered: order_item.quantity,
          status: :pending,
          service_case: false
        )
      end

      { success: true, delivery: delivery }
    else
      { success: false, errors: delivery.errors }
    end
  end

  def reschedule_order(new_date, reason = nil)
    @order.update!(
      status: :rescheduled
    )

    # Crear nota de reprogramación
    @order.order_items.update_all(
      notes: "Reprogramado para #{new_date}. Razón: #{reason}"
    )

    { success: true, message: "Pedido reprogramado exitosamente" }
  end

  def mark_items_as_ready(item_ids)
    items = @order.order_items.where(id: item_ids)
    items.update_all(status: :ready)

    # Verificar si el pedido completo está listo
    @order.check_and_update_status!

    { success: true, ready_items: items.count }
  end
end

class DeliveryFailureService
  def initialize(delivery, reason: nil, reschedule_days: 7)
    @delivery = delivery
    @reason = reason || "Entrega fracasada - reagendada automáticamente"
    @reschedule_days = reschedule_days
  end

  def call
    ActiveRecord::Base.transaction do
      # 1. Marcar la entrega original como fracasada
      mark_as_failed!

      # 2. Clonar la entrega para una semana después
      new_delivery = clone_delivery!

      # 3. Notificar a los involucrados
      notify_failure(new_delivery)

      new_delivery
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Error al procesar entrega fracasada: #{e.message}")
    raise
  end

  private

  def mark_as_failed!
    @delivery.update!(
      status: :failed,
      reschedule_reason: @reason
    )

    # Marcar todos los delivery_items como failed
    @delivery.delivery_items.where.not(status: [ :delivered, :cancelled ])
             .update_all(status: DeliveryItem.statuses[:failed], updated_at: Time.current)
  end

  def clone_delivery!
    new_date = @delivery.delivery_date + @reschedule_days.days

    # Crear nueva entrega
    new_delivery = Delivery.create!(
      order: @delivery.order,
      delivery_address: @delivery.delivery_address,
      delivery_date: new_date,
      contact_name: @delivery.contact_name,
      contact_phone: @delivery.contact_phone,
      contact_id: @delivery.contact_id,
      delivery_time_preference: @delivery.delivery_time_preference,
      delivery_notes: "Reagendada por entrega fracasada del #{@delivery.delivery_date.strftime('%d/%m/%Y')}. Motivo: #{@reason}",
      delivery_type: @delivery.delivery_type,
      status: :scheduled,
      approved: true
    )

    # Clonar delivery_items que no fueron entregados
    @delivery.delivery_items.where.not(status: [ :delivered, :cancelled ]).each do |item|
      DeliveryItem.create!(
        delivery: new_delivery,
        order_item: item.order_item,
        quantity_delivered: item.quantity_delivered,
        status: :pending,
        service_case: item.service_case,
        notes: item.notes
      )
    end

    new_delivery
  end

  def notify_failure(new_delivery)
    users = []
    # Logística y producción
    users += User.where(role: [ :logistics, :production_manager ])
    # Vendedor del pedido
    users << @delivery.order.seller.user if @delivery.order.seller&.user.present?

    message = <<~MSG.strip
      La entrega del pedido #{@delivery.order.number} programada para #{I18n.l(@delivery.delivery_date, format: :long)} fracasó.
      Se creó una nueva entrega para #{I18n.l(new_delivery.delivery_date, format: :long)}.
    MSG

    NotificationService.create_for_users(users.compact.uniq, new_delivery, message, type: "delivery_failed")
  end
end

# app/services/notification_service.rb
class NotificationService
  # Configuración de correos externos para reagendamientos
  RESCHEDULE_NOTIFICATION_EMAILS = ENV.fetch("RESCHEDULE_NOTIFICATION_EMAILS", "").split(",").map(&:strip)

  def self.create_for_users(users, notifiable, message, type: "generic", send_email: true)
    users = Array(users)
    admin_users = User.where(role: :admin)
    all_users = (users + admin_users).uniq

    # Inserta notificaciones en la BD
    notifications = all_users.map do |user|
      {
        user_id: user.id,
        notifiable_type: notifiable.class.name,
        notifiable_id: notifiable.id,
        message: message,
        read: false,
        notification_type: type,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    Notification.insert_all(notifications) if notifications.any?

    # Envía correo solo si send_email = true
    if send_email
      all_users.each do |user|
        NotificationMailer.safe_notify(
          user_id: user.id,
          message: message,
          type: type,
          notifiable_id: notifiable.id,
          notifiable_type: notifiable.class.name
        )
      end
    end
  end

  def self.notify_order_ready_for_delivery(order)
    logistics_users = User.where(role: :logistics)
    message = "El pedido #{order.number} está listo para entrega"
    create_for_users(logistics_users, order, message)
  end

  # ✅ MÉTODO MEJORADO PARA REAGENDAMIENTOS
  def self.notify_delivery_rescheduled(delivery, rescheduled_by: nil, reason: nil)
    seller = delivery.order.seller.user

    # Mensaje detallado para correos externos
    detailed_message = <<~MSG.strip
      La entrega del pedido #{delivery.order.number} fue reprogramada para #{delivery.delivery_date.strftime('%d/%m/%Y')}.

      Cliente: #{delivery.order.client.name}
      Dirección: #{delivery.delivery_address.address}
      Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})
      #{"Motivo: #{reason}" if reason.present?}
      #{"Reagendado por: #{rescheduled_by}" if rescheduled_by.present?}
    MSG

    # Notificación interna al vendedor (ya se hace en Rescheduler para otros roles)
    simple_message = "La entrega del pedido #{delivery.order.number} fue reprogramada para #{delivery.delivery_date.strftime('%d/%m/%Y')}"
    create_for_users([ seller ], delivery, simple_message, type: "reschedule_delivery")

    # ✅ Envío de correos a cuentas externas
    if RESCHEDULE_NOTIFICATION_EMAILS.any?
      RESCHEDULE_NOTIFICATION_EMAILS.each do |email|
        NotificationMailer.safe_notify_external(
          email: email,
          message: detailed_message,
          type: "reschedule_delivery",
          notifiable_id: delivery.id,
          notifiable_type: "Delivery"
        )
      end
    end
  end

  def self.notify_route_assigned(delivery_plan)
    if delivery_plan.driver
      message = "Se te asignó una nueva ruta para la semana #{delivery_plan.week}/#{delivery_plan.year}"
      create_for_users([ delivery_plan.driver ], delivery_plan, message)
    end
  end
end

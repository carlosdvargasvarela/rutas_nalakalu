# app/services/notification_service.rb
class NotificationService
  # Configuración de correos externos para reagendamientos
  RESCHEDULE_NOTIFICATION_EMAILS = ENV.fetch("RESCHEDULE_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  PLAN_EMAIL = ENV.fetch("PLAN_EMAIL", "plan@nalakalu.com")

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
  def self.notify_delivery_rescheduled(delivery, old_date:, rescheduled_by: nil, reason: nil)
    seller = delivery.order.seller.user

    formatted_old = I18n.l old_date, format: :long
    formatted_new = I18n.l delivery.delivery_date, format: :long

    # 👉 Mensaje claro
    simple_message = "La entrega del pedido #{delivery.order.number} fue reagendada del #{formatted_old} al #{formatted_new}."

    # Notificación interna (solo una vez!)
    create_for_users([ seller ], delivery, simple_message, type: "reschedule_delivery", send_email: false)

    # Mensaje detallado para correos externos
    detailed_message = <<~MSG.strip
      La entrega del pedido #{delivery.order.number} fue reprogramada:
      📅 Del #{formatted_old} al #{formatted_new}

      Cliente: #{delivery.order.client.name}
      Dirección: #{delivery.delivery_address.address}
      Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})
      #{"Motivo: #{reason}" if reason.present?}
      #{"Reagendado por: #{rescheduled_by}" if rescheduled_by.present?}
    MSG

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

  # ✅ NUEVO: Entrega creada en semana ISO actual
  def self.notify_current_week_delivery_created(delivery, created_by: nil)
    return unless delivery_in_current_iso_week?(delivery)
    # No correo para mandados internos
    send_email_to_plan = !delivery.internal_delivery?

    message = current_week_created_message(delivery, created_by: created_by)

    # Notificación interna: admins, logística y seller
    users = []
    users += User.where(role: %i[admin logistics]).to_a
    users << delivery.order.seller&.user
    create_for_users(users.compact.uniq, delivery, message, type: "current_week_delivery", send_email: false)

    # Correo externo a plan@
    if send_email_to_plan
      NotificationMailer.safe_notify_external(
        email: PLAN_EMAIL,
        message: message,
        type: "current_week_delivery",
        notifiable_id: delivery.id,
        notifiable_type: "Delivery"
      )
    end
  end

  # ✅ NUEVO: Entrega reagendada a semana ISO actual
  def self.notify_current_week_delivery_rescheduled(delivery, old_date:, rescheduled_by: nil, reason: nil)
    return unless delivery_in_current_iso_week?(delivery)
    # No correo para mandados internos
    send_email_to_plan = !delivery.internal_delivery?

    message = current_week_rescheduled_message(delivery, old_date: old_date, rescheduled_by: rescheduled_by, reason: reason)

    # Notificación interna: admins, logística y seller
    users = []
    users += User.where(role: %i[admin logistics]).to_a
    users << delivery.order.seller&.user
    create_for_users(users.compact.uniq, delivery, message, type: "current_week_reschedule", send_email: false)

    # Correo externo a plan@
    if send_email_to_plan
      NotificationMailer.safe_notify_external(
        email: PLAN_EMAIL,
        message: message,
        type: "current_week_reschedule",
        notifiable_id: delivery.id,
        notifiable_type: "Delivery"
      )
    end
  end

  # -----------------------
  # Helpers privados
  # -----------------------
  def self.delivery_in_current_iso_week?(delivery)
    # Reutiliza tu lógica ISO ya existente
    delivery.needs_approval?
  end
  private_class_method :delivery_in_current_iso_week?

  def self.current_week_created_message(delivery, created_by: nil)
    fecha = I18n.l(delivery.delivery_date, format: :long)
    productos = delivery.delivery_items.includes(order_item: :order).map do |di|
      prod = di.order_item&.product || "-"
      qty  = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Nueva entrega programada en la semana actual (ISO):",
      "📅 Fecha: #{fecha}",
      "📦 Pedido: #{delivery.order.number}",
      "👤 Cliente: #{delivery.order.client.name}",
      "📍 Dirección: #{delivery.delivery_address.address}#{delivery.delivery_address.description.present? ? " (#{delivery.delivery_address.description})" : ""}",
      "🏷️ Tipo: #{delivery.display_type}",
      "👨‍💼 Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})",
      (created_by.present? ? "✍️ Creada por: #{created_by}" : nil),
      "Productos:",
      productos
    ].compact.join("\n")
  end
  private_class_method :current_week_created_message

  def self.current_week_rescheduled_message(delivery, old_date:, rescheduled_by: nil, reason: nil)
    old_f = I18n.l(old_date, format: :long)
    new_f = I18n.l(delivery.delivery_date, format: :long)
    productos = delivery.delivery_items.includes(order_item: :order).map do |di|
      prod = di.order_item&.product || "-"
      qty  = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Entrega reagendada en la semana actual (ISO):",
      "📦 Pedido: #{delivery.order.number}",
      "📅 Del: #{old_f}",
      "📅 Al:  #{new_f}",
      "👤 Cliente: #{delivery.order.client.name}",
      "📍 Dirección: #{delivery.delivery_address.address}#{delivery.delivery_address.description.present? ? " (#{delivery.delivery_address.description})" : ""}",
      "🏷️ Tipo: #{delivery.display_type}",
      "👨‍💼 Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})",
      (reason.present? ? "📝 Motivo: #{reason}" : nil),
      (rescheduled_by.present? ? "🔁 Reagendado por: #{rescheduled_by}" : nil),
      "Productos:",
      productos
    ].compact.join("\n")
  end
  private_class_method :current_week_rescheduled_message
end

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
    create_for_users([seller], delivery, simple_message, type: "reschedule_delivery", send_email: false)

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
      create_for_users([delivery_plan.driver], delivery_plan, message)
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

  # ✅ NUEVO: Alerta diaria de entregas pendientes de confirmar para la próxima semana
  def self.send_daily_next_week_pending_confirmations!
    # Calcular rango de la próxima semana ISO
    next_week_start, next_week_end = IsoWeekHelper.next_iso_week_range

    # Buscar entregas que cumplen las condiciones
    pending_deliveries = Delivery
      .where(status: :scheduled)
      .where(approved: true)
      .where(archived: false)
      .where(delivery_date: next_week_start..next_week_end)
      .where.not(delivery_type: :internal_delivery)
      .includes(order: [:client, :seller], delivery_address: :client, delivery_items: {order_item: :order})

    return if pending_deliveries.empty?

    Rails.logger.info "[NextWeekPendingConfirmations] Encontradas #{pending_deliveries.count} entregas pendientes para la próxima semana (#{next_week_start} - #{next_week_end})"

    # Agrupar por seller
    deliveries_by_seller = pending_deliveries.group_by { |d| d.order.seller }

    # Enviar correo a cada seller
    deliveries_by_seller.each do |seller, deliveries|
      next unless seller&.user

      message = build_next_week_pending_message_for_seller(seller, deliveries, next_week_start, next_week_end)

      # Enviar correo directo al seller (respetando send_notifications)
      NotificationMailer.safe_notify(
        user_id: seller.user.id,
        message: message,
        type: "next_week_pending_confirmation",
        notifiable_id: nil,
        notifiable_type: nil
      )

      Rails.logger.info "[NextWeekPendingConfirmations] Correo enviado a seller: #{seller.user.email} (#{deliveries.count} entregas)"
    end

    # Enviar correo global a todos los admins
    admin_users = User.where(role: :admin)
    if admin_users.any?
      message = build_next_week_pending_message_for_admins(pending_deliveries, next_week_start, next_week_end)

      admin_users.each do |admin|
        NotificationMailer.safe_notify(
          user_id: admin.id,
          message: message,
          type: "next_week_pending_confirmation",
          notifiable_id: nil,
          notifiable_type: nil
        )
      end

      Rails.logger.info "[NextWeekPendingConfirmations] Correo enviado a #{admin_users.count} administradores"
    end
  end

  # -----------------------
  # Helpers privados
  # -----------------------
  def self.delivery_in_current_iso_week?(delivery)
    IsoWeekHelper.in_current_iso_week?(delivery.delivery_date)
  end
  private_class_method :delivery_in_current_iso_week?

  def self.current_week_created_message(delivery, created_by: nil)
    fecha = I18n.l(delivery.delivery_date, format: :long)
    productos = delivery.delivery_items.includes(order_item: :order).map do |di|
      prod = di.order_item&.product || "-"
      qty = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Nueva entrega programada en la semana actual (ISO):",
      "📅 Fecha: #{fecha}",
      "📦 Pedido: #{delivery.order.number}",
      "👤 Cliente: #{delivery.order.client.name}",
      "📍 Dirección: #{delivery.delivery_address.address}#{" (#{delivery.delivery_address.description})" if delivery.delivery_address.description.present?}",
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
      qty = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Entrega reagendada en la semana actual (ISO):",
      "📦 Pedido: #{delivery.order.number}",
      "📅 Del: #{old_f}",
      "📅 Al:  #{new_f}",
      "👤 Cliente: #{delivery.order.client.name}",
      "📍 Dirección: #{delivery.delivery_address.address}#{" (#{delivery.delivery_address.description})" if delivery.delivery_address.description.present?}",
      "🏷️ Tipo: #{delivery.display_type}",
      "👨‍💼 Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})",
      (reason.present? ? "📝 Motivo: #{reason}" : nil),
      (rescheduled_by.present? ? "🔁 Reagendado por: #{rescheduled_by}" : nil),
      "Productos:",
      productos
    ].compact.join("\n")
  end
  private_class_method :current_week_rescheduled_message

  # ✅ NUEVO: Construir mensaje para seller
  def self.build_next_week_pending_message_for_seller(seller, deliveries, start_date, end_date)
    seller_name = seller.name.presence || seller.user.name.presence || seller.user.email
    formatted_range = "#{I18n.l(start_date, format: :short)} - #{I18n.l(end_date, format: :short)}"

    message = "🔔 Hola #{seller_name},\n\n"
    message += "Tienes #{deliveries.count} entrega(s) pendiente(s) de confirmar para la próxima semana (#{formatted_range}):\n\n"

    deliveries.sort_by(&:delivery_date).each do |delivery|
      fecha = I18n.l(delivery.delivery_date, format: :long)
      order_number = delivery.order.number
      client_name = delivery.order.client.name
      address = delivery.delivery_address.address
      address += " (#{delivery.delivery_address.description})" if delivery.delivery_address.description.present?

      message += "📦 Pedido ##{order_number}\n"
      message += "   📅 Fecha: #{fecha}\n"
      message += "   👤 Cliente: #{client_name}\n"
      message += "   📍 Dirección: #{address}\n"
      message += "   🏷️ Tipo: #{delivery.display_type}\n"
      message += "   ⚠️ Estado: #{delivery.display_status}\n\n"
    end

    message += "Por favor, confirma estas entregas con tus clientes lo antes posible para que logística pueda planificar las rutas.\n\n"
    message += "Saludos,\nEquipo NaLakalu"

    message
  end
  private_class_method :build_next_week_pending_message_for_seller

  # ✅ NUEVO: Construir mensaje para admins
  def self.build_next_week_pending_message_for_admins(deliveries, start_date, end_date)
    formatted_range = "#{I18n.l(start_date, format: :short)} - #{I18n.l(end_date, format: :short)}"

    message = "📊 Resumen de entregas pendientes de confirmar para la próxima semana (#{formatted_range}):\n\n"
    message += "Total de entregas: #{deliveries.count}\n\n"

    # Agrupar por seller para el resumen
    by_seller = deliveries.group_by { |d| d.order.seller }

    by_seller.each do |seller, seller_deliveries|
      seller_name = seller&.name || "Sin vendedor"
      seller_code = seller&.seller_code || "N/A"

      message += "👨‍💼 #{seller_name} (#{seller_code}): #{seller_deliveries.count} entrega(s)\n"

      seller_deliveries.sort_by(&:delivery_date).each do |delivery|
        fecha = I18n.l(delivery.delivery_date, format: :short)
        order_number = delivery.order.number
        client_name = delivery.order.client.name

        message += "   • #{fecha} - Pedido ##{order_number} - #{client_name}\n"
      end

      message += "\n"
    end

    message += "Recuerda coordinar con los vendedores para confirmar estas entregas.\n\n"
    message += "Saludos,\nSistema NaLakalu"

    message
  end
  private_class_method :build_next_week_pending_message_for_admins
end

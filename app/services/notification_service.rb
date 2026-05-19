# app/services/notification_service.rb
class NotificationService
  # Configuración de correos externos para reagendamientos
  RESCHEDULE_NOTIFICATION_EMAILS = ENV.fetch("RESCHEDULE_NOTIFICATION_EMAILS", "").split(",").map(&:strip)
  PLAN_EMAIL = ENV.fetch("PLAN_EMAIL", "plan@nalakalu.com")

  def self.create_for_users(users, notifiable, message, type: "generic", send_email: true)
    users = Array(users)
    admin_users = User.where(role: :admin)
    all_users = (users + admin_users).compact.uniq

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
    seller_user = delivery.order.seller&.user

    formatted_old = I18n.l old_date, format: :long
    formatted_new = I18n.l delivery.delivery_date, format: :long

    simple_message = "La entrega del pedido #{delivery.order.number} fue reagendada del #{formatted_old} al #{formatted_new}."
    simple_message += " Por: #{rescheduled_by}." if rescheduled_by.present?

    # Notificación interna: logística + admin + seller
    users = User.where(role: [:logistics, :admin]).to_a
    users << seller_user
    create_for_users(users.compact.uniq, delivery, simple_message, type: "reschedule_delivery", send_email: false)

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

  # ✅ NUEVO: Entrega reagendada — fecha original O nueva en semana ISO actual
  def self.notify_current_week_delivery_rescheduled(delivery, old_date:, rescheduled_by: nil, reason: nil)
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

  # ✅ Reagendamiento masivo de ítems: un solo correo con todos los productos
  def self.notify_bulk_items_rescheduled(original_delivery:, items:, target_delivery:, rescheduled_by: nil, reason: nil)
    return if items.empty?

    message = build_bulk_reschedule_message(
      original_delivery, items, target_delivery,
      rescheduled_by: rescheduled_by, reason: reason
    )

    # Notificación interna sin correo
    users = User.where(role: %i[admin logistics]).to_a
    users << original_delivery.order.seller&.user
    create_for_users(users.compact.uniq, target_delivery, message, type: "reschedule_delivery", send_email: false)

    return if original_delivery.internal_delivery?

    # Un solo correo a RESCHEDULE_NOTIFICATION_EMAILS
    RESCHEDULE_NOTIFICATION_EMAILS.each do |email|
      NotificationMailer.safe_notify_external(
        email: email,
        message: message,
        type: "reschedule_delivery",
        notifiable_id: target_delivery.id,
        notifiable_type: "Delivery"
      )
    end

    # Correo a plan@ solo si alguna de las fechas cae en la semana ISO actual
    old_in_current = IsoWeekHelper.in_current_iso_week?(original_delivery.delivery_date)
    new_in_current = IsoWeekHelper.in_current_iso_week?(target_delivery.delivery_date)
    return unless old_in_current || new_in_current

    NotificationMailer.safe_notify_external(
      email: PLAN_EMAIL,
      message: message,
      type: "current_week_reschedule",
      notifiable_id: target_delivery.id,
      notifiable_type: "Delivery"
    )
  rescue => e
    Rails.logger.error("⚠️ notify_bulk_items_rescheduled falló: #{e.message}")
  end

  # ✅ Notificación cuando se cancela un producto de una entrega
  def self.notify_item_cancelled(delivery_item, cancelled_by: nil)
    delivery = delivery_item.delivery
    seller_user = delivery.order.seller&.user
    product = delivery_item.order_item&.product || "-"
    qty = delivery_item.quantity_delivered || 1
    order_number = delivery.order.number

    message = "El producto '#{product}' (x#{qty}) del pedido #{order_number} fue cancelado."
    message += " Por: #{cancelled_by}." if cancelled_by.present?

    # Notificación interna: logística + admin + seller
    users = User.where(role: [:logistics, :admin]).to_a
    users << seller_user
    create_for_users(users.compact.uniq, delivery, message, type: "item_cancelled", send_email: false)

    # Correo externo a plan@ si la entrega es de la semana actual y no es mandado interno
    return if delivery.internal_delivery?
    return unless IsoWeekHelper.in_current_iso_week?(delivery.delivery_date)

    NotificationMailer.safe_notify_external(
      email: PLAN_EMAIL,
      message: build_item_cancelled_message(delivery_item, cancelled_by: cancelled_by),
      type: "item_cancelled",
      notifiable_id: delivery.id,
      notifiable_type: "Delivery"
    )
  end

  # ✅ NUEVO: Alerta diaria de entregas pendientes de confirmar para la próxima semana
  def self.send_daily_next_week_pending_confirmations!
    next_week_start, next_week_end = IsoWeekHelper.next_iso_week_range

    pending_deliveries = Delivery
      .where(status: :scheduled)
      .where(approved: true)
      .where(archived: false)
      .where(delivery_date: next_week_start..next_week_end)
      .where.not(delivery_type: :internal_delivery)
      .includes(order: [:client, :seller], delivery_address: :client, delivery_items: {order_item: :order})

    return if pending_deliveries.empty?

    Rails.logger.info "[NextWeekPendingConfirmations] Encontradas #{pending_deliveries.count} entregas pendientes para la próxima semana (#{next_week_start} - #{next_week_end})"

    deliveries_by_seller = pending_deliveries.group_by { |d| d.order.seller }

    deliveries_by_seller.each do |seller, deliveries|
      next unless seller&.user

      message = build_next_week_pending_message_for_seller(seller, deliveries, next_week_start, next_week_end)

      NotificationMailer.safe_notify(
        user_id: seller.user.id,
        message: message,
        type: "next_week_pending_confirmation",
        notifiable_id: nil,
        notifiable_type: nil
      )

      Rails.logger.info "[NextWeekPendingConfirmations] Correo enviado a seller: #{seller.user.email} (#{deliveries.count} entregas)"
    end

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

  def self.build_bulk_reschedule_message(original_delivery, items, target_delivery, rescheduled_by: nil, reason: nil)
    old_f = I18n.l(original_delivery.delivery_date, format: :long)
    new_f = I18n.l(target_delivery.delivery_date, format: :long)
    motivo  = reason.present?        ? reason        : "El usuario no agregó motivos"
    usuario = rescheduled_by.present? ? rescheduled_by : "No especificado"

    productos = items.map do |di|
      prod = di.order_item&.product || "-"
      qty  = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Productos reagendados (reagendamiento masivo):",
      "Pedido: #{original_delivery.order.number}",
      "Del: #{old_f}",
      "Al:  #{new_f}",
      "Cliente: #{original_delivery.order.client.name}",
      "Direccion: #{original_delivery.delivery_address.address}#{" (#{original_delivery.delivery_address.description})" if original_delivery.delivery_address.description.present?}",
      "Tipo: #{original_delivery.display_type}",
      "Vendedor: #{original_delivery.order.seller.name} (#{original_delivery.order.seller.seller_code})",
      "Motivo: #{motivo}",
      "Reagendado por: #{usuario}",
      "",
      "Productos:",
      productos
    ].join("\n")
  end
  private_class_method :build_bulk_reschedule_message

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

  # ✅ ACTUALIZADO: Sin emojis, motivo y reagendado por siempre presentes con fallback
  def self.current_week_rescheduled_message(delivery, old_date:, rescheduled_by: nil, reason: nil)
    old_f = I18n.l(old_date, format: :long)
    new_f = I18n.l(delivery.delivery_date, format: :long)

    motivo_texto = reason.present? ? reason : "El usuario no agregó motivos"
    usuario_texto = rescheduled_by.present? ? rescheduled_by : "No especificado"

    productos = delivery.delivery_items.includes(order_item: :order).map do |di|
      prod = di.order_item&.product || "-"
      qty = di.quantity_delivered || 1
      "- #{prod} x #{qty}"
    end.join("\n")

    [
      "Entrega reagendada en la semana actual (ISO):",
      "Pedido: #{delivery.order.number}",
      "Del: #{old_f}",
      "Al:  #{new_f}",
      "Cliente: #{delivery.order.client.name}",
      "Direccion: #{delivery.delivery_address.address}#{" (#{delivery.delivery_address.description})" if delivery.delivery_address.description.present?}",
      "Tipo: #{delivery.display_type}",
      "Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})",
      "Motivo: #{motivo_texto}",
      "Reagendado por: #{usuario_texto}",
      "",
      "Productos:",
      productos
    ].join("\n")
  end
  private_class_method :current_week_rescheduled_message

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

  def self.build_item_cancelled_message(delivery_item, cancelled_by: nil)
    delivery = delivery_item.delivery
    product = delivery_item.order_item&.product || "-"
    qty = delivery_item.quantity_delivered || 1
    fecha = I18n.l(delivery.delivery_date, format: :long)

    [
      "Producto cancelado en entrega de semana actual:",
      "Pedido: #{delivery.order.number}",
      "Cliente: #{delivery.order.client.name}",
      "Producto: #{product} x #{qty}",
      "Fecha de entrega: #{fecha}",
      "Vendedor: #{delivery.order.seller.name} (#{delivery.order.seller.seller_code})",
      ("Cancelado por: #{cancelled_by}" if cancelled_by.present?)
    ].compact.join("\n")
  end
  private_class_method :build_item_cancelled_message

  def self.build_next_week_pending_message_for_admins(deliveries, start_date, end_date)
    formatted_range = "#{I18n.l(start_date, format: :short)} - #{I18n.l(end_date, format: :short)}"

    message = "📊 Resumen de entregas pendientes de confirmar para la próxima semana (#{formatted_range}):\n\n"
    message += "Total de entregas: #{deliveries.count}\n\n"

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

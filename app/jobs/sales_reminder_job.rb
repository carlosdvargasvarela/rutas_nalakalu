class SalesReminderJob < ApplicationJob
  queue_as :default

  def perform(period)
    Rails.logger.info "Ejecutando SalesReminderJob para periodo: #{period}"

    case period
    when "weekly"
      send_weekly_reminders
    when "daily"
      send_daily_reminders
      send_next_week_pending_confirmations
    else
      Rails.logger.warn "Periodo desconocido para SalesReminderJob: #{period}"
    end
  end

  private

  def send_weekly_reminders
    Seller.includes(:user, orders: :deliveries).find_each do |seller|
      # Contar pedidos pendientes del vendedor
      pending_orders = Order.where(seller_id: seller.id)
        .where(status: [:pending, :in_production])
        .count

      # Contar entregas programadas para esta semana
      current_week = Date.current.beginning_of_week
      deliveries_this_week = Delivery.joins(:order)
        .where(orders: {seller_id: seller.id})
        .where(delivery_date: current_week..current_week.end_of_week)
        .where(status: [:scheduled, :ready_to_deliver, :in_route])
        .count

      # Crear notificación semanal usando NotificationService
      message = build_weekly_message(seller, pending_orders, deliveries_this_week)

      NotificationService.create_for_users(
        [seller.user],
        seller,
        message,
        type: "weekly_reminder",
        send_email: true
      )

      Rails.logger.info "Recordatorio semanal enviado a #{seller.user.email}"
    end
  end

  def send_daily_reminders
    today = Date.current

    Seller.includes(:user, orders: :deliveries).find_each do |seller|
      # Pedidos de este seller con entregas para hoy y en estado correcto
      deliveries_today = Delivery.joins(:order)
        .where(orders: {seller_id: seller.id})
        .where(delivery_date: today)
        .where(status: [:scheduled, :ready_to_deliver, :in_route])

      next if deliveries_today.empty?

      message = "¡Buenos días! Tienes #{deliveries_today.count} entrega(s) programada(s) para hoy. " \
                "Revisa el estado de tus pedidos y coordina con el equipo de logística."

      # Notifica usando NotificationService
      NotificationService.create_for_users(
        [seller.user],
        seller,
        message,
        type: "daily_reminder",
        send_email: true
      )

      Rails.logger.info "Recordatorio diario enviado a #{seller.user.email}"
    end
  end

  def build_weekly_message(seller, pending_orders, deliveries_this_week)
    seller_name = seller.name.presence || seller.user.name.presence || seller.user.email

    message = "¡Resumen semanal para #{seller_name}!\n\n"
    message += "📋 Pedidos pendientes: #{pending_orders}\n"
    message += "🚚 Entregas esta semana: #{deliveries_this_week}\n\n"

    if pending_orders > 0
      message += "• Revisa el estado de tus pedidos pendientes\n"
    end

    if deliveries_this_week > 0
      message += "• Coordina con logística para las entregas de esta semana\n"
    end

    message += "\n¡Que tengas una excelente semana!"
    message
  end

  def send_next_week_pending_confirmations
    # Calcular el rango de la próxima semana (lunes a viernes)
    next_monday = Date.current.next_week(:monday)
    next_saturday = next_monday + 5.days

    Seller.includes(:user, orders: :deliveries).find_each do |seller|
      # Buscar entregas de la próxima semana asociadas al vendedor
      deliveries_next_week = Delivery.joins(:order)
        .where(orders: {seller_id: seller.id})
        .where(delivery_date: next_monday..next_saturday)
        .where(status: [:scheduled, :ready_to_deliver])
        .includes(:delivery_items)

      # Filtrar solo las entregas con delivery_items NO confirmados
      pending_deliveries = deliveries_next_week.select do |delivery|
        delivery.delivery_items.any? { |di| di.status != "confirmed" }
      end

      next if pending_deliveries.empty?

      # Construir mensaje
      message = "🔔 Entregas pendientes de confirmar para la próxima semana (#{next_monday.strftime("%d/%m")} - #{next_saturday.strftime("%d/%m")}):\n\n"
      pending_deliveries.each do |delivery|
        day = I18n.l(delivery.delivery_date, format: "%A %d/%m")
        order_number = delivery.order.number
        client_name = delivery.order.client.name
        message += "• Pedido ##{order_number} para #{client_name} el #{day}\n"
      end
      message += "\nPor favor, confirma estas entregas con tus clientes lo antes posible."

      # Crear notificación usando NotificationService
      NotificationService.create_for_users(
        [seller.user],
        seller,
        message,
        type: "next_week_pending_confirmation",
        send_email: true
      )

      Rails.logger.info "Notificación de entregas pendientes de confirmar para la próxima semana enviada a #{seller.user.email}"
    end
  end
end

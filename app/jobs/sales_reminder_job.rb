class SalesReminderJob < ApplicationJob
  queue_as :default

  def perform(period)
    Rails.logger.info "Ejecutando SalesReminderJob para periodo: #{period}"

    case period
    when "weekly"
      send_weekly_reminders
    when "daily"
      send_daily_reminders
    else
      Rails.logger.warn "Periodo desconocido para SalesReminderJob: #{period}"
    end
  end

  private

  def send_weekly_reminders
    Seller.includes(:user, orders: :deliveries).find_each do |seller|
      # Contar pedidos pendientes del vendedor
      pending_orders = Order.where(seller_id: seller.id)
                           .where(status: [ :pending, :in_production ])
                           .count

      # Contar entregas programadas para esta semana
      current_week = Date.current.beginning_of_week
      deliveries_this_week = Delivery.joins(:order)
                                   .where(orders: { seller_id: seller.id })
                                   .where(delivery_date: current_week..current_week.end_of_week)
                                   .where(status: [ :scheduled, :ready_to_deliver, :in_route ])
                                   .count

      # Crear notificación semanal
      message = build_weekly_message(seller, pending_orders, deliveries_this_week)

      Notification.create!(
        user: seller.user,
        message: message,
        notification_type: "weekly_reminder",
        notifiable: seller
      )

      Rails.logger.info "Recordatorio semanal enviado a #{seller.user.email}"
    end
  end

  def send_daily_reminders
    today = Date.current

    Seller.includes(:user, orders: :deliveries).find_each do |seller|
      # Pedidos de este seller con entregas para hoy y en estado correcto
      deliveries_today = Delivery.joins(:order)
        .where(orders: { seller_id: seller.id })
        .where(delivery_date: today)
        .where(status: [ :scheduled, :ready_to_deliver, :in_route ])

      next if deliveries_today.empty?

      message = "¡Buenos días! Tienes #{deliveries_today.count} entrega(s) programada(s) para hoy. " \
                "Revisa el estado de tus pedidos y coordina con el equipo de logística."

      # Notifica al usuario asociado al seller
      Notification.create!(
        user: seller.user,
        message: message,
        notification_type: "daily_reminder",
        notifiable: seller
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
end

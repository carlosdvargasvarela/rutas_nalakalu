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
    # Obtener todos los vendedores activos
    sellers = User.where(role: :seller)

    sellers.each do |seller|
      # Contar pedidos pendientes del vendedor
      pending_orders = Order.joins(:seller)
                           .where(sellers: { id: seller.id })
                           .where(status: [ :pending, :in_production ])
                           .count

      # Contar entregas programadas para esta semana
      current_week = Date.current.beginning_of_week
      deliveries_this_week = Delivery.joins(order: :seller)
                                   .where(sellers: { id: seller.id })
                                   .where(delivery_date: current_week..current_week.end_of_week)
                                   .where(status: [ :pending, :in_transit ])
                                   .count

      # Crear notificación semanal
      message = build_weekly_message(seller, pending_orders, deliveries_this_week)

      Notification.create!(
        user: seller,
        message: message,
        notification_type: "weekly_reminder"
      )

      Rails.logger.info "Recordatorio semanal enviado a #{seller.email}"
    end
  end

  def send_daily_reminders
    # Obtener vendedores con entregas para hoy
    today = Date.current

    sellers_with_deliveries_today = User.joins(sellers: { orders: :deliveries })
                                       .where(role: :seller)
                                       .where(deliveries: { delivery_date: today })
                                       .where(deliveries: { status: [ :pending, :in_transit ] })
                                       .distinct

    sellers_with_deliveries_today.each do |seller|
      # Contar entregas de hoy
      todays_deliveries = Delivery.joins(order: :seller)
                                .where(sellers: { id: seller.id })
                                .where(delivery_date: today)
                                .where(status: [ :pending, :in_transit ])
                                .count

      # Crear notificación diaria
      message = "¡Buenos días! Tienes #{todays_deliveries} entrega(s) programada(s) para hoy. " \
                "Revisa el estado de tus pedidos y coordina con el equipo de logística."

      Notification.create!(
        user: seller,
        message: message,
        notification_type: "daily_reminder"
      )

      Rails.logger.info "Recordatorio diario enviado a #{seller.email}"
    end
  end

  def build_weekly_message(seller, pending_orders, deliveries_this_week)
    message = "¡Resumen semanal para #{seller.name}!\n\n"
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

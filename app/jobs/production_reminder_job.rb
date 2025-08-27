class ProductionReminderJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Ejecutando ProductionReminderJob"

    # Obtener gerentes de producción
    production_managers = User.where(role: :production_manager)

    production_managers.each do |manager|
      # Obtener estadísticas de producción
      stats = get_production_stats

      # Crear notificación con resumen usando NotificationService
      message = build_production_message(stats)

      NotificationService.create_for_users(
        [ manager ],
        manager,
        message,
        type: "production_reminder",
        send_email: true
      )

      Rails.logger.info "Recordatorio de producción enviado a #{manager.email}"
    end

    # También notificar si hay pedidos urgentes
    notify_urgent_orders
  end

  private

  def get_production_stats
    {
      pending_orders: Order.where(status: :pending).count,
      in_production: Order.where(status: :in_production).count,
      ready_for_delivery: Order.where(status: :ready_for_delivery).count,
      overdue_orders: get_overdue_orders_count,
      this_week_deliveries: get_this_week_deliveries_count
    }
  end

  def get_overdue_orders_count
    # Pedidos que deberían estar listos pero aún están en producción
    # (asumiendo que tienen más de 7 días en producción)
    Order.where(status: :in_production)
         .where("updated_at < ?", 7.days.ago)
         .count
  end

  def get_this_week_deliveries_count
    current_week = Date.current.beginning_of_week
    Delivery.where(delivery_date: current_week..current_week.end_of_week)
            .where(status: [ :pending, :in_transit ])
            .count
  end

  def build_production_message(stats)
    message = "📊 Resumen de Producción - Semana del #{Date.current.beginning_of_week.strftime('%d/%m')}\n\n"
    message += "🔄 Pedidos pendientes: #{stats[:pending_orders]}\n"
    message += "🏭 En producción: #{stats[:in_production]}\n"
    message += "✅ Listos para entrega: #{stats[:ready_for_delivery]}\n"
    message += "🚚 Entregas esta semana: #{stats[:this_week_deliveries]}\n"

    if stats[:overdue_orders] > 0
      message += "\n⚠️ ATENCIÓN: #{stats[:overdue_orders]} pedido(s) con retraso en producción\n"
    end

    message += "\n📋 Tareas recomendadas:\n"
    message += "• Revisar el estado de los pedidos en producción\n"
    message += "• Coordinar con logística para las entregas de esta semana\n"
    message += "• Actualizar el estado de los pedidos completados\n"

    if stats[:overdue_orders] > 0
      message += "• URGENTE: Revisar pedidos con retraso\n"
    end

    message
  end

  def notify_urgent_orders
    # Notificar sobre pedidos muy urgentes (más de 10 días en producción)
    urgent_orders = Order.where(status: :in_production)
                        .where("updated_at < ?", 10.days.ago)

    if urgent_orders.any?
      # Notificar a todos los gerentes de producción y admins
      urgent_users = User.where(role: [ :production_manager, :admin ])

      # Usar el primer pedido urgente como notifiable (o podrías crear un objeto específico)
      first_urgent_order = urgent_orders.first

      message = "🚨 ALERTA URGENTE: #{urgent_orders.count} pedido(s) llevan más de 10 días en producción.\n\n"
      message += "Pedidos afectados:\n"

      urgent_orders.limit(5).each do |order|
        days_in_production = (Date.current - order.updated_at.to_date).to_i
        message += "• Pedido ##{order.number} - #{days_in_production} días\n"
      end

      if urgent_orders.count > 5
        message += "• ... y #{urgent_orders.count - 5} más\n"
      end

      message += "\n¡Requiere atención inmediata!"

      NotificationService.create_for_users(
        urgent_users,
        first_urgent_order,
        message,
        type: "urgent_alert",
        send_email: true
      )

      Rails.logger.warn "Alerta urgente enviada: #{urgent_orders.count} pedidos con retraso crítico"
    end
  end
end
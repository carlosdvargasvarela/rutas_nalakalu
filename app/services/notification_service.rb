# app/services/notification_service.rb
class NotificationService
  def self.create_for_users(users, notifiable, message, type: "generic", send_email: true)
    users = Array(users)
    admin_users = User.where(role: :admin)
    all_users = (users + admin_users).uniq

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

    if send_email
      all_users.each do |user|
        NotificationMailer.with(user:, message:, notifiable:, type:).generic_notification.deliver_later
      end
    end
  end

  def self.notify_order_ready_for_delivery(order)
    logistics_users = User.where(role: :logistics)
    message = "El pedido #{order.number} está listo para entrega"
    create_for_users(logistics_users, order, message)
  end

  def self.notify_delivery_rescheduled(delivery)
    seller = delivery.order.seller.user
    message = "La entrega del pedido #{delivery.order.number} fue reprogramada para #{delivery.delivery_date.strftime('%d/%m/%Y')}"
    create_for_users([ seller ], delivery, message)
  end

  def self.notify_route_assigned(delivery_plan)
    if delivery_plan.driver
      message = "Se te asignó una nueva ruta para la semana #{delivery_plan.week}/#{delivery_plan.year}"
      create_for_users([ delivery_plan.driver ], delivery_plan, message)
    end
  end
end

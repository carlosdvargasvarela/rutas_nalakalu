# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.recent.includes(:notifiable)
    @grouped_notifications = @notifications.group_by(&:notification_type)
    @unread_count = current_user.notifications.unread.count
  end

  def mark_as_read
    notification = current_user.notifications.find(params[:id])
    notification.mark_as_read!
    redirect_back(fallback_location: notifications_path)
  end

  def mark_all_as_read
    current_user.notifications.unread.update_all(read: true)
    redirect_to notifications_path, notice: "Todas las notificaciones fueron marcadas como leídas"
  end

  def mark_group_as_read
    notification_type = params[:notification_type]

    current_user.notifications
      .where(notification_type: notification_type, read: false)
      .update_all(read: true)

    redirect_to notifications_path, notice: "Todas las notificaciones de tipo '#{helpers.notification_type_label(notification_type)}' fueron marcadas como leídas"
  end
end

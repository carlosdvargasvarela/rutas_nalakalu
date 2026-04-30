class NotificationsController < ApplicationController
  after_action :verify_authorized

  def index
    authorize Notification

    # Inicializamos Ransack con el scope de Pundit
    @q = policy_scope(Notification).recent.ransack(params[:q])

    # Obtenemos resultados paginados
    @notifications = @q.result.includes(:notifiable).page(params[:page]).per(15)

    # Stats para la sidebar
    @unread_count = policy_scope(Notification).unread.count

    # Contamos por tipo (esto ignora el filtro actual para mostrar totales correctos en la sidebar)
    @types_counts = policy_scope(Notification).group(:notification_type).count
  end

  def mark_as_read
    @notification = policy_scope(Notification).find(params[:id])
    authorize @notification
    @notification.mark_as_read!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  def mark_all_as_read
    authorize Notification
    policy_scope(Notification).unread.update_all(read: true)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to notifications_path, notice: "Notificaciones leídas" }
    end
  end
end

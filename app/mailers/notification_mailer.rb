# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  default from: "notificaciones@nalakalu.com"

  def generic_notification
    @user_id       = params[:user_id]
    @message       = params[:message]
    @notifiable_id = params[:notifiable_id]
    @notifiable_type = params[:notifiable_type]
    @type          = params[:type]

    @user = User.find_by(id: @user_id)
    return unless @user&.send_notifications?

    # Buscar objeto notifiable si aplica
    if @notifiable_id && @notifiable_type
      @notifiable = safe_lookup(@notifiable_type, @notifiable_id)
    end

    mail(
      to: @user.email,
      subject: subject_for(@type, @notifiable)
    )
  end

  # Notificación para correos externos (sin user_id)
  def external_notification
    @message       = params[:message]
    @notifiable_id = params[:notifiable_id]
    @notifiable_type = params[:notifiable_type]
    @type          = params[:type]

    @notifiable = safe_lookup(@notifiable_type, @notifiable_id)

    mail(
      to: params[:email],
      subject: subject_for(@type, @notifiable)
    )
  end

  private

  def safe_lookup(type, id)
    type.constantize.find_by(id: id)
  rescue NameError => e
    Rails.logger.warn "Clase no encontrada: #{type} - #{e.message}"
    nil
  end

  def subject_for(type, notifiable = nil)
    case type
    when "production_reminder" then "📊 Recordatorio de Producción"
    when "weekly_reminder"     then "📋 Resumen Semanal de Ventas"
    when "daily_reminder"      then "🔔 Recordatorio Diario de Entregas"
    when "urgent_alert"        then "🚨 Alerta Urgente de Producción"
    when "next_week_pending_confirmation" then "🔔 Entregas pendientes de confirmar para la próxima semana"
    when "reschedule_delivery"
      if notifiable.is_a?(Delivery) && notifiable.order.present?
        "🔄 Pedido ##{notifiable.order.number} reagendado"
      else
        "🔄 Pedido reagendado"
      end
    when "current_week_delivery"
      if notifiable.is_a?(Delivery) && notifiable.order.present?
        "📦 Nueva entrega (semana actual) – Pedido ##{notifiable.order.number}"
      else
        "📦 Nueva entrega (semana actual)"
      end
    when "current_week_reschedule"
      if notifiable.is_a?(Delivery) && notifiable.order.present?
        "🔄 Reagenda (semana actual) – Pedido ##{notifiable.order.number}"
      else
        "🔄 Reagenda (semana actual)"
      end
    else
      "Notificación del Sistema"
    end
  end

  def self.safe_notify(user_id:, message:, type:, notifiable_id: nil, notifiable_type: nil)
    with(
      user_id: user_id,
      message: message,
      type: type,
      notifiable_id: notifiable_id,
      notifiable_type: notifiable_type
    ).generic_notification.deliver_later
  end

  def self.safe_notify_external(email:, message:, type:, notifiable_id: nil, notifiable_type: nil)
    with(
      email: email,
      message: message,
      type: type,
      notifiable_id: notifiable_id,
      notifiable_type: notifiable_type
    ).external_notification.deliver_later
  end
end

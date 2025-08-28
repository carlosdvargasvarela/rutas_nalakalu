# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  default from: "notificaciones@nalakalu.com"

  def generic_notification
    @user_id       = params[:user_id]
    @message       = params[:message]
    @notifiable_id = params[:notifiable_id]
    @notifiable_type = params[:notifiable_type]
    @type          = params[:type]

    # Buscar el usuario de forma segura
    @user = User.find_by(id: @user_id)
    return unless @user # Si el usuario no existe, no enviar correo

    # Buscar el objeto notifiable de forma segura (si existe)
    if @notifiable_id && @notifiable_type
      begin
        @notifiable = @notifiable_type.constantize.find_by(id: @notifiable_id)
      rescue NameError => e
        Rails.logger.warn "Clase no encontrada: #{@notifiable_type} - #{e.message}"
        @notifiable = nil
      end
    end

    mail(
      to: @user.email,
      subject: subject_for(@type)
    )
  end

  private

  def subject_for(type)
    case type
    when "production_reminder" then "📊 Recordatorio de Producción"
    when "weekly_reminder" then "📋 Resumen Semanal de Ventas"
    when "daily_reminder" then "🔔 Recordatorio Diario de Entregas"
    when "urgent_alert"   then "🚨 Alerta Urgente de Producción"
    else "Notificación del Sistema"
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
end
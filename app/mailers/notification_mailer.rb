# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  default from: "notificaciones@nalakalu.com"

  def generic_notification
    @user       = params[:user]
    @message    = params[:message]
    @notifiable = params[:notifiable]
    @type       = params[:type]

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
end

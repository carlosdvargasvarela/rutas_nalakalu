class TestJob < ApplicationJob
  queue_as :default

  def perform(message = "Test ejecutado correctamente")
    Rails.logger.info "🧪 TestJob ejecutado: #{message}"

    # Crear una notificación de prueba para el primer admin
    admin = User.where(role: :admin).first

    if admin
      Notification.create!(
        user: admin,
        message: "🧪 Job de prueba ejecutado exitosamente: #{message}",
        notification_type: "system_test",
        notifiable: admin # Asociamos al propio admin
      )

      Rails.logger.info "Notificación de prueba enviada a #{admin.email}"
    else
      Rails.logger.warn "No se encontró ningún admin para enviar la notificación de prueba"
    end
  end
end

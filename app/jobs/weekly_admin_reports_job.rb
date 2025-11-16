# app/jobs/weekly_admin_reports_job.rb
class WeeklyAdminReportsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[WeeklyAdminReportsJob] Iniciando generación de informes semanales a las #{Time.current}"

    begin
      # Informe 1: Entregas no confirmadas
      AdminReports::WeeklyUnconfirmedDeliveries.generate_and_send!

      # Informe 2: Errores en direcciones
      AdminReports::AddressErrorsReport.generate_and_send!

      Rails.logger.info "[WeeklyAdminReportsJob] Informes semanales generados y enviados exitosamente"
    rescue StandardError => e
      Rails.logger.error "[WeeklyAdminReportsJob] Error durante la generación de informes: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end

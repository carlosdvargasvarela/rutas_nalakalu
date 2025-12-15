# app/jobs/next_week_pending_confirmations_job.rb
class NextWeekPendingConfirmationsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[NextWeekPendingConfirmationsJob] Iniciando ejecución diaria a las #{Time.current}"

    begin
      NotificationService.send_daily_next_week_pending_confirmations!
      Rails.logger.info "[NextWeekPendingConfirmationsJob] Ejecución completada exitosamente"
    rescue => e
      Rails.logger.error "[NextWeekPendingConfirmationsJob] Error durante la ejecución: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end

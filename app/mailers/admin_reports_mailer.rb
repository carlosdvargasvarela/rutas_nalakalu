# app/mailers/admin_reports_mailer.rb
class AdminReportsMailer < ApplicationMailer
  default from: "NaLakalu Notificaciones <alerts@nalakalu.com>"

  def weekly_unconfirmed_deliveries(recipient:, report_data:, excel_file:)
    @report_data = report_data
    @recipient = recipient

    attachments["entregas_no_confirmadas_#{report_data[:week_start].strftime('%Y%m%d')}.xlsx"] = excel_file.read

    mail(
      to: recipient,
      subject: "📊 Informe Semanal: Entregas No Confirmadas (#{report_data[:week_start].strftime('%d/%m')} - #{report_data[:week_end].strftime('%d/%m/%Y')})"
    )
  end

  def weekly_unconfirmed_deliveries_empty(recipient:, week_start:, week_end:)
    @week_start = week_start
    @week_end = week_end
    @recipient = recipient

    mail(
      to: recipient,
      subject: "✅ Informe Semanal: Sin Entregas Pendientes de Confirmar (#{week_start.strftime('%d/%m')} - #{week_end.strftime('%d/%m/%Y')})"
    )
  end

  def address_errors_report(recipient:, report_data:, excel_file:)
    @report_data = report_data
    @recipient = recipient

    attachments["errores_direccion_#{report_data[:week_start].strftime('%Y%m%d')}.xlsx"] = excel_file.read

    mail(
      to: recipient,
      subject: "⚠️ Informe Semanal: Errores en Direcciones (#{report_data[:week_start].strftime('%d/%m')} - #{report_data[:week_end].strftime('%d/%m/%Y')})"
    )
  end

  def address_errors_report_empty(recipient:, week_start:, week_end:)
    @week_start = week_start
    @week_end = week_end
    @recipient = recipient

    mail(
      to: recipient,
      subject: "✅ Informe Semanal: Sin Errores de Dirección (#{week_start.strftime('%d/%m')} - #{week_end.strftime('%d/%m/%Y')})"
    )
  end
end
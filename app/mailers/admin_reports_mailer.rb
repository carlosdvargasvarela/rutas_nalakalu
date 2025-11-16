# app/mailers/admin_reports_mailer.rb
class AdminReportsMailer < ApplicationMailer
  default from: "reportes@nalakalu.com"

  # report_data: hash serializable
  # delivery_ids: array de IDs de Delivery
  def weekly_unconfirmed_deliveries(recipient:, report_data:, delivery_ids:)
    @report_data = report_data
    @recipient = recipient

    deliveries = Delivery
                   .where(id: delivery_ids)
                   .includes(order: [ :client, :seller ], delivery_address: :client, delivery_items: { order_item: :order })

    excel_stream = generate_unconfirmed_deliveries_excel(deliveries)
    filename = "entregas_no_confirmadas_#{report_data[:week_start].strftime('%Y%m%d')}.xlsx"

    attachments[filename] = excel_stream.string

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

  def address_errors_report(recipient:, report_data:, delivery_ids:)
    @report_data = report_data
    @recipient = recipient

    deliveries = Delivery
                   .where(id: delivery_ids)
                   .includes(order: [ :client, :seller ], delivery_address: :client)

    excel_stream = generate_address_errors_excel(deliveries)
    filename = "errores_direccion_#{report_data[:week_start].strftime('%Y%m%d')}.xlsx"

    attachments[filename] = excel_stream.string

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

  private

  def generate_unconfirmed_deliveries_excel(deliveries)
    package = Axlsx::Package.new
    workbook = package.workbook

    header_style = workbook.styles.add_style(
      bg_color: "0066CC",
      fg_color: "FFFFFF",
      b: true,
      alignment: { horizontal: :center, vertical: :center, wrap_text: true }
    )

    date_style = workbook.styles.add_style(
      format_code: "dd/mm/yyyy"
    )

    workbook.add_worksheet(name: "Entregas No Confirmadas") do |sheet|
      sheet.add_row([
        "Fecha de Entrega",
        "Pedido",
        "Cliente",
        "Vendedor",
        "Código Vendedor",
        "Email Vendedor",
        "Dirección",
        "Descripción Dirección",
        "Tipo de Entrega",
        "Estado",
        "En Plan de Ruta",
        "Notas"
      ], style: header_style)

      deliveries.each do |delivery|
        seller = delivery.order.seller
        in_plan = delivery.delivery_plans.any? ? "Sí" : "No"

        sheet.add_row([
          delivery.delivery_date,
          delivery.order.number,
          delivery.order.client.name,
          seller&.name || "N/A",
          seller&.seller_code || "N/A",
          seller&.user&.email || "N/A",
          delivery.delivery_address.address,
          delivery.delivery_address.description,
          delivery.display_type,
          delivery.display_status,
          in_plan,
          delivery.delivery_notes
        ], style: [ date_style, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ])
      end

      sheet.column_widths(12, 15, 25, 20, 15, 25, 35, 25, 20, 18, 12, 30)
    end

    package.to_stream
  end

  def generate_address_errors_excel(deliveries)
    package = Axlsx::Package.new
    workbook = package.workbook

    header_style = workbook.styles.add_style(
      bg_color: "CC0000",
      fg_color: "FFFFFF",
      b: true,
      alignment: { horizontal: :center, vertical: :center, wrap_text: true }
    )

    date_style = workbook.styles.add_style(
      format_code: "dd/mm/yyyy"
    )

    error_style = workbook.styles.add_style(
      fg_color: "CC0000",
      b: true
    )

    workbook.add_worksheet(name: "Errores de Dirección") do |sheet|
      sheet.add_row([
        "Fecha de Entrega",
        "Pedido",
        "Cliente",
        "Vendedor",
        "Código Vendedor",
        "Email Vendedor",
        "Dirección",
        "Descripción",
        "Latitud",
        "Longitud",
        "Errores Detectados",
        "Calidad Geocodificación",
        "Estado Entrega"
      ], style: header_style)

      deliveries.each do |delivery|
        seller = delivery.order.seller
        address = delivery.delivery_address
        errors = address.error_summary

        sheet.add_row([
          delivery.delivery_date,
          delivery.order.number,
          delivery.order.client.name,
          seller&.name || "N/A",
          seller&.seller_code || "N/A",
          seller&.user&.email || "N/A",
          address.address,
          address.description,
          address.latitude,
          address.longitude,
          errors,
          address.geocode_quality,
          delivery.display_status
        ], style: [ date_style, nil, nil, nil, nil, nil, nil, nil, nil, nil, error_style, nil, nil ])
      end

      sheet.column_widths(12, 15, 25, 20, 15, 25, 35, 25, 12, 12, 40, 20, 18)
    end

    package.to_stream
  end
end

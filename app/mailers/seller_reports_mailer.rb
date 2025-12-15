# app/mailers/seller_reports_mailer.rb
class SellerReportsMailer < ApplicationMailer
  default from: "reportes@nalakalu.com"

  # =========================
  # Errores de dirección - semana actual
  # =========================
  def address_errors_current_week(seller:, recipient:, report_data:, delivery_ids:)
    @seller = seller
    @report_data = report_data
    @recipient = recipient

    deliveries = Delivery
      .where(id: delivery_ids)
      .includes(order: [:client, :seller], delivery_address: :client)

    excel_stream = generate_address_errors_excel(deliveries)
    filename = "errores_direccion_semana_actual_#{report_data[:week_start].strftime("%Y%m%d")}_#{seller.seller_code}.xlsx"

    attachments[filename] = excel_stream.string

    mail(
      to: recipient,
      subject: "⚠️ Tus entregas con errores de dirección - Semana actual (#{report_data[:week_start].strftime("%d/%m")} - #{report_data[:week_end].strftime("%d/%m/%Y")})"
    )
  end

  def address_errors_current_week_empty(seller:, recipient:, week_start:, week_end:)
    @seller = seller
    @week_start = week_start
    @week_end = week_end
    @recipient = recipient

    mail(
      to: recipient,
      subject: "✅ Sin errores de dirección en tus entregas - Semana actual (#{week_start.strftime("%d/%m")} - #{week_end.strftime("%d/%m/%Y")})"
    )
  end

  # =========================
  # Errores de dirección - semana siguiente
  # =========================
  def address_errors_next_week(seller:, recipient:, report_data:, delivery_ids:)
    @seller = seller
    @report_data = report_data
    @recipient = recipient

    deliveries = Delivery
      .where(id: delivery_ids)
      .includes(order: [:client, :seller], delivery_address: :client)

    excel_stream = generate_address_errors_excel(deliveries)
    filename = "errores_direccion_semana_siguiente_#{report_data[:week_start].strftime("%Y%m%d")}_#{seller.seller_code}.xlsx"

    attachments[filename] = excel_stream.string

    mail(
      to: recipient,
      subject: "⚠️ Revisa direcciones de tus entregas - Semana siguiente (#{report_data[:week_start].strftime("%d/%m")} - #{report_data[:week_end].strftime("%d/%m/%Y")})"
    )
  end

  def address_errors_next_week_empty(seller:, recipient:, week_start:, week_end:)
    @seller = seller
    @week_start = week_start
    @week_end = week_end
    @recipient = recipient

    mail(
      to: recipient,
      subject: "✅ Sin errores de dirección en tus entregas - Semana siguiente (#{week_start.strftime("%d/%m")} - #{week_end.strftime("%d/%m/%Y")})"
    )
  end

  private

  # Reutilizamos una versión similar a la de AdminReportsMailer,
  # pero pensada para el vendedor (solo sus entregas).
  def generate_address_errors_excel(deliveries)
    package = Axlsx::Package.new
    workbook = package.workbook

    header_style = workbook.styles.add_style(
      bg_color: "CC0000",
      fg_color: "FFFFFF",
      b: true,
      alignment: {horizontal: :center, vertical: :center, wrap_text: true}
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
        "Dirección",
        "Descripción",
        "Latitud",
        "Longitud",
        "Errores Detectados",
        "Calidad Geocodificación",
        "Estado Entrega"
      ], style: header_style)

      deliveries.each do |delivery|
        address = delivery.delivery_address
        next if address.nil?

        sheet.add_row([
          delivery.delivery_date,
          delivery.order.number,
          delivery.order.client.name,
          address.address,
          address.description,
          address.latitude,
          address.longitude,
          address.error_summary,
          address.geocode_quality,
          delivery.display_status
        ], style: [date_style, nil, nil, nil, nil, nil, nil, error_style, nil, nil])
      end

      sheet.column_widths(12, 15, 25, 35, 25, 12, 12, 40, 20, 18)
    end

    package.to_stream
  end
end

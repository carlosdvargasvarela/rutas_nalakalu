# app/services/admin_reports/weekly_unconfirmed_deliveries.rb
module AdminReports
  class WeeklyUnconfirmedDeliveries
    def self.generate_and_send!(reference_date: Date.current)
      new(reference_date).generate_and_send!
    end

    def initialize(reference_date)
      @reference_date = reference_date
      @prev_week_start, @prev_week_end = calculate_previous_week
    end

    def generate_and_send!
      Rails.logger.info "[WeeklyUnconfirmedDeliveries] Generando informe para semana #{@prev_week_start} - #{@prev_week_end}"

      deliveries = fetch_unconfirmed_deliveries

      if deliveries.empty?
        Rails.logger.info "[WeeklyUnconfirmedDeliveries] No hay entregas sin confirmar para la semana pasada"
        send_empty_report
        return
      end

      Rails.logger.info "[WeeklyUnconfirmedDeliveries] Encontradas #{deliveries.count} entregas sin confirmar"

      report_data = build_report_data(deliveries)
      excel_file = generate_excel(deliveries)

      send_report(report_data, excel_file)
    end

    private

    def calculate_previous_week
      # Semana ISO pasada
      current_week_start = @reference_date.beginning_of_week(:monday)
      prev_week_start = current_week_start - 1.week
      prev_week_end = prev_week_start + 6.days
      [ prev_week_start, prev_week_end ]
    end

    def fetch_unconfirmed_deliveries
      Delivery
        .where(delivery_date: @prev_week_start..@prev_week_end)
        .where(confirmed_by_vendor: false)
        .where(approved: true)
        .where(archived: false)
        .where.not(delivery_type: :internal_delivery)
        .includes(order: [ :client, :seller ], delivery_address: :client, delivery_items: { order_item: :order })
        .order(:delivery_date, "orders.number")
    end

    def build_report_data(deliveries)
      by_seller = deliveries.group_by { |d| d.order.seller }

      seller_summary = by_seller.map do |seller, seller_deliveries|
        {
          name: seller&.name || "Sin vendedor",
          code: seller&.seller_code || "N/A",
          email: seller&.user&.email || "N/A",
          count: seller_deliveries.count
        }
      end.sort_by { |s| -s[:count] }

      {
        week_start: @prev_week_start,
        week_end: @prev_week_end,
        total_count: deliveries.count,
        seller_summary: seller_summary,
        top_sellers: seller_summary.first(5)
      }
    end

    def generate_excel(deliveries)
      package = Axlsx::Package.new
      workbook = package.workbook

      # Estilos
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
        # Encabezados
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

        # Datos
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

        # Ajustar anchos de columna
        sheet.column_widths(12, 15, 25, 20, 15, 25, 35, 25, 20, 18, 12, 30)
      end

      package.to_stream
    end

    def send_report(report_data, excel_file)
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.weekly_unconfirmed_deliveries(
          recipient: recipient,
          report_data: report_data,
          excel_file: excel_file
        ).deliver_later
      end

      Rails.logger.info "[WeeklyUnconfirmedDeliveries] Informe enviado a #{recipients.count} destinatarios"
    end

    def send_empty_report
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.weekly_unconfirmed_deliveries_empty(
          recipient: recipient,
          week_start: @prev_week_start,
          week_end: @prev_week_end
        ).deliver_later
      end

      Rails.logger.info "[WeeklyUnconfirmedDeliveries] Informe vacío enviado a #{recipients.count} destinatarios"
    end

    def build_recipients_list
      recipients = []

      # Correos de ENV
      env_emails = ENV.fetch("ADMIN_REPORTS_EMAILS", "").split(",").map(&:strip).reject(&:blank?)
      recipients += env_emails

      # Admins con notificaciones activas
      admin_emails = User.where(role: :admin, send_notifications: true).pluck(:email)
      recipients += admin_emails

      recipients.uniq
    end
  end
end

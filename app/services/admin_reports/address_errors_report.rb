# app/services/admin_reports/address_errors_report.rb
module AdminReports
  class AddressErrorsReport
    def self.generate_and_send!(reference_date: Date.current)
      new(reference_date).generate_and_send!
    end

    def initialize(reference_date)
      @reference_date = reference_date
      @prev_week_start, @prev_week_end = calculate_previous_week
    end

    def generate_and_send!
      Rails.logger.info "[AddressErrorsReport] Generando informe para semana #{@prev_week_start} - #{@prev_week_end}"

      deliveries_with_errors = fetch_deliveries_with_address_errors

      if deliveries_with_errors.empty?
        Rails.logger.info "[AddressErrorsReport] No hay entregas con errores de dirección para la semana pasada"
        send_empty_report
        return
      end

      Rails.logger.info "[AddressErrorsReport] Encontradas #{deliveries_with_errors.count} entregas con errores de dirección"

      report_data = build_report_data(deliveries_with_errors)
      delivery_ids = deliveries_with_errors.map(&:id)

      send_report(report_data, delivery_ids)
    end

    private

    def calculate_previous_week
      current_week_start = @reference_date.beginning_of_week(:monday)
      prev_week_start = current_week_start - 1.week
      prev_week_end = prev_week_start + 6.days
      [prev_week_start, prev_week_end]
    end

    def fetch_deliveries_with_address_errors
      all_deliveries = Delivery
        .where(delivery_date: @prev_week_start..@prev_week_end)
        .where(approved: true)
        .where(archived: false)
        .where.not(delivery_type: :internal_delivery)
        .includes(order: [:client, :seller], delivery_address: :client)
        .order(:delivery_date, "orders.number")

      # Filtrar solo las que tienen errores
      all_deliveries.select { |d| d.delivery_address.has_address_errors? }
    end

    def build_report_data(deliveries)
      by_seller = deliveries.group_by { |d| d.order.seller }

      seller_summary = by_seller.map do |seller, seller_deliveries|
        error_types = seller_deliveries.flat_map { |d| d.delivery_address.address_errors }.uniq
        {
          name: seller&.name || "Sin vendedor",
          code: seller&.seller_code || "N/A",
          email: seller&.user&.email || "N/A",
          count: seller_deliveries.count,
          main_errors: error_types.first(3).join(", ")
        }
      end.sort_by { |s| -s[:count] }

      # Resumen por tipo de error
      all_errors = deliveries.flat_map { |d| d.delivery_address.address_errors }
      error_type_summary = all_errors.group_by(&:itself).transform_values(&:count).sort_by { |_, v| -v }

      {
        week_start: @prev_week_start,
        week_end: @prev_week_end,
        total_count: deliveries.count,
        affected_sellers_count: by_seller.keys.count,
        seller_summary: seller_summary,
        top_sellers: seller_summary.first(5),
        error_type_summary: error_type_summary
      }
    end

    def send_report(report_data, delivery_ids)
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.address_errors_report(
          recipient: recipient,
          report_data: report_data,
          delivery_ids: delivery_ids
        ).deliver_later
      end

      Rails.logger.info "[AddressErrorsReport] Informe enviado a #{recipients.count} destinatarios"
    end

    def send_empty_report
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.address_errors_report_empty(
          recipient: recipient,
          week_start: @prev_week_start,
          week_end: @prev_week_end
        ).deliver_later
      end

      Rails.logger.info "[AddressErrorsReport] Informe vacío enviado a #{recipients.count} destinatarios"
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

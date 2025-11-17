# app/services/admin_reports/current_week_unconfirmed_deliveries.rb
module AdminReports
  class CurrentWeekUnconfirmedDeliveries
    def self.generate_and_send!(reference_date: Date.current)
      new(reference_date).generate_and_send!
    end

    def initialize(reference_date)
      @reference_date = reference_date
      @week_start, @week_end = calculate_current_week
    end

    def generate_and_send!
      Rails.logger.info "[CurrentWeekUnconfirmedDeliveries] Generando informe para semana #{@week_start} - #{@week_end}"

      deliveries = fetch_unconfirmed_deliveries

      if deliveries.empty?
        Rails.logger.info "[CurrentWeekUnconfirmedDeliveries] No hay entregas sin confirmar para esta semana"
        send_empty_report
        return
      end

      Rails.logger.info "[CurrentWeekUnconfirmedDeliveries] Encontradas #{deliveries.count} entregas sin confirmar para esta semana"

      report_data = build_report_data(deliveries)
      delivery_ids = deliveries.map(&:id)

      send_report(report_data, delivery_ids)
    end

    private

    def calculate_current_week
      week_start = @reference_date.beginning_of_week(:monday)
      week_end   = week_start + 6.days
      [ week_start, week_end ]
    end

    def fetch_unconfirmed_deliveries
      Delivery
        .where(delivery_date: @week_start..@week_end)
        .where(confirmed_by_vendor: false)
        .where(approved: true)
        .where(archived: false)
        # Excluir estados que ya no requieren confirmación
        .where.not(status: [ :delivered, :rescheduled, :archived, :cancelled, :ready_to_deliver ])
        # Excluir entregas internas
        .where.not(delivery_type: :internal_delivery)
        # Excluir entregas de tienda / pickup (ajusta el símbolo al enum real)
        .where.not(delivery_type: :store_pickup)
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
        week_start: @week_start,
        week_end: @week_end,
        total_count: deliveries.count,
        seller_summary: seller_summary,
        top_sellers: seller_summary.first(5)
      }
    end

    def send_report(report_data, delivery_ids)
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.current_week_unconfirmed_deliveries(
          recipient: recipient,
          report_data: report_data,
          delivery_ids: delivery_ids
        ).deliver_later
      end

      Rails.logger.info "[CurrentWeekUnconfirmedDeliveries] Informe enviado a #{recipients.count} destinatarios"
    end

    def send_empty_report
      recipients = build_recipients_list

      recipients.each do |recipient|
        AdminReportsMailer.current_week_unconfirmed_deliveries_empty(
          recipient: recipient,
          week_start: @week_start,
          week_end: @week_end
        ).deliver_later
      end

      Rails.logger.info "[CurrentWeekUnconfirmedDeliveries] Informe vacío enviado a #{recipients.count} destinatarios"
    end

    def build_recipients_list
      recipients = []

      env_emails = ENV.fetch("ADMIN_REPORTS_EMAILS", "").split(",").map(&:strip).reject(&:blank?)
      recipients += env_emails

      admin_emails = User.where(role: :admin, send_notifications: true).pluck(:email)
      recipients += admin_emails

      recipients.uniq
    end
  end
end

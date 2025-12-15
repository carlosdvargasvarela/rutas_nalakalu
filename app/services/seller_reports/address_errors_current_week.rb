# app/services/seller_reports/address_errors_current_week.rb
module SellerReports
  class AddressErrorsCurrentWeek
    def self.generate_and_send!(reference_date: Date.current)
      new(reference_date).generate_and_send!
    end

    def initialize(reference_date)
      @reference_date = reference_date
      @week_start, @week_end = calculate_current_week
    end

    def generate_and_send!
      Rails.logger.info "[SellerReports::AddressErrorsCurrentWeek] Generando informe para #{@week_start} - #{@week_end}"

      deliveries_with_errors = fetch_deliveries_with_address_errors

      if deliveries_with_errors.empty?
        Rails.logger.info "[SellerReports::AddressErrorsCurrentWeek] No hay entregas con errores de dirección esta semana"
        send_empty_reports_to_sellers_with_notifications
        return
      end

      deliveries_by_seller = deliveries_with_errors.group_by { |d| d.order.seller }

      deliveries_by_seller.each do |seller, seller_deliveries|
        next if seller.nil?
        user = seller.user
        next if user.nil? || user.email.blank? || !user.send_notifications?

        report_data = build_report_data_for_seller(seller, seller_deliveries)
        delivery_ids = seller_deliveries.map(&:id)

        SellerReportsMailer.address_errors_current_week(
          seller: seller,
          recipient: user.email,
          report_data: report_data,
          delivery_ids: delivery_ids
        ).deliver_later

        Rails.logger.info "[SellerReports::AddressErrorsCurrentWeek] Informe enviado a vendedor #{seller.id} (#{user.email}) con #{seller_deliveries.count} entregas"
      end
    end

    private

    def calculate_current_week
      week_start = @reference_date.beginning_of_week(:monday)
      week_end = week_start + 6.days
      [week_start, week_end]
    end

    def fetch_deliveries_with_address_errors
      all_deliveries = Delivery
        .where(delivery_date: @week_start..@week_end)
        .where(approved: true)
        .where(archived: false)
        .where.not(delivery_type: :internal_delivery)
        .includes(order: [:client, :seller], delivery_address: :client)
        .order(:delivery_date, "orders.number")

      all_deliveries.select do |delivery|
        addr = delivery.delivery_address
        addr.present? && addr.has_address_errors?
      end
    end

    def build_report_data_for_seller(seller, deliveries)
      {
        week_start: @week_start,
        week_end: @week_end,
        total_count: deliveries.count,
        seller_name: seller.name,
        seller_code: seller.seller_code,
        seller_email: seller.user&.email
      }
    end

    # En caso de que quieras avisar a los vendedores incluso cuando NO tienen errores,
    # podemos enviarles un correo "vacío". Si no lo deseas, puedes eliminar este método
    # y la llamada desde generate_and_send!.
    def send_empty_reports_to_sellers_with_notifications
      Seller
        .includes(:user)
        .where.not(user: {id: nil})
        .where(users: {send_notifications: true})
        .find_each do |seller|
          user = seller.user
          next if user.email.blank?

          SellerReportsMailer.address_errors_current_week_empty(
            seller: seller,
            recipient: user.email,
            week_start: @week_start,
            week_end: @week_end
          ).deliver_later

          Rails.logger.info "[SellerReports::AddressErrorsCurrentWeek] Informe vacío enviado a vendedor #{seller.id} (#{user.email})"
        end
    end
  end
end

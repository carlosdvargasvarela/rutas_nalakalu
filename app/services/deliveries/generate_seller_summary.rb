# app/services/deliveries/generate_seller_summary.rb
module Deliveries
  class GenerateSellerSummary
    def call
      summaries = {}

      # Calcular ventana de tiempo
      now = Time.current.in_time_zone("America/Costa_Rica")
      window_start = (now - 13.hours).beginning_of_day + 18.hours  # 18:00 del día anterior
      window_end = now.beginning_of_day + 7.hours                   # 07:00 de hoy

      # Entregas creadas en la ventana de tiempo (excluyendo archivadas)
      new_deliveries = Delivery
        .where.not(status: :archived)
        .where("deliveries.created_at >= ? AND deliveries.created_at <= ?", window_start, window_end)
        .includes(
          order: [:client, :seller],
          delivery_address: :client,
          delivery_items: {order_item: :order}
        )
        .order(:created_at)

      return summaries if new_deliveries.empty?

      # Agrupar por vendedor
      new_deliveries.group_by { |d| d.order.seller_id }.each do |seller_id, deliveries|
        summaries[seller_id] = {
          deliveries: deliveries,
          summary: build_summary(deliveries)
        }
      end

      summaries
    end

    private

    def build_summary(deliveries)
      deliveries_with_errors = deliveries.select { |d| has_delivery_errors?(d) }

      # Agregar errores por categoría
      error_categories = Hash.new(0)
      deliveries_with_errors.each do |delivery|
        detector = Deliveries::ErrorDetector.new(delivery)
        detector.error_summary.each do |category, count|
          error_categories[category] += count
        end
      end

      {
        total_count: deliveries.count,
        total_items: deliveries.sum { |d| d.delivery_items.count },
        with_errors: deliveries_with_errors.count,
        error_categories: error_categories.sort_by { |_, v| -v }.to_h,
        date_range: {
          start: deliveries.min_by(&:created_at)&.created_at,
          end: deliveries.max_by(&:created_at)&.created_at
        }
      }
    end

    def has_delivery_errors?(delivery)
      Deliveries::ErrorDetector.new(delivery).has_errors?
    end
  end
end

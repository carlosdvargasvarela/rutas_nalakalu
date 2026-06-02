# app/services/deliveries/service_case_detector.rb
module Deliveries
  class ServiceCaseDetector
    KEYWORDS = %w[
      caso\ de\ servicio
      caso\ servicio
      recoleccion
      devolucion
    ].freeze

    TERMINAL_STATUSES = %w[rescheduled cancelled archived delivered].freeze

    def initialize(delivery)
      @delivery = delivery
    end

    def actionable_items
      delivery.delivery_items.select do |item|
        next false if item.status.in?(TERMINAL_STATUSES)

        name = normalize(item.order_item.product)

        item.service_case? || KEYWORDS.any? { |kw| name.include?(kw) }
      end
    end

    def requires_service_case?
      actionable_items.any?
    end

    private

    attr_reader :delivery

    def normalize(text)
      text.to_s.downcase
        .unicode_normalize(:nfkd)
        .gsub(/[^\x00-\x7F]/, "")
    end
  end
end

# app/services/deliveries/repair_service_detector.rb
module Deliveries
  class RepairServiceDetector
    KEYWORDS = %w[
      servicio\ de\ reparacion
      servicio\ reparacion
    ].freeze

    TERMINAL_STATUSES = %w[rescheduled cancelled archived delivered].freeze

    def initialize(delivery)
      @delivery = delivery
    end

    def actionable_items
      delivery.delivery_items.select do |item|
        next false if item.status.in?(TERMINAL_STATUSES)

        name = normalize(item.order_item.product)
        KEYWORDS.any? { |kw| name.include?(kw) }
      end
    end

    def requires_repair_service?
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

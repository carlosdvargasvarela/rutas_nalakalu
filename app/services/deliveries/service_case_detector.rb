# app/services/deliveries/service_case_detector.rb
module Deliveries
  class ServiceCaseDetector
    KEYWORDS = [
      "caso de servicio"
    ].freeze

    TERMINAL_STATUSES = %w[rescheduled cancelled archived delivered].freeze

    def initialize(delivery)
      @delivery = delivery
    end

    def actionable_items
      delivery.delivery_items.select do |item|
        next false if item.status.in?(TERMINAL_STATUSES)

        name = normalize(item.order_item.product)

        name.include?("caso de servicio") || item.service_case?
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

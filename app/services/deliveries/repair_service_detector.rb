# app/services/deliveries/repair_service_detector.rb
module Deliveries
  class RepairServiceDetector
    TERMINAL_STATUSES = %w[rescheduled cancelled archived delivered].freeze

    def initialize(delivery)
      @delivery = delivery
    end

    def actionable_items
      delivery.delivery_items.select do |item|
        next false if item.status.in?(TERMINAL_STATUSES)

        name = normalize(item.order_item.product)
        keywords.any? { |kw| name.include?(kw) }
      end
    end

    def requires_repair_service?
      actionable_items.any?
    end

    private

    attr_reader :delivery

    # Lookup is per-instance (not a class constant) so admin edits to
    # /admin/deliveries_vocabulary take effect without restarting the app.
    def keywords
      @keywords ||= Deliveries::Vocabulary.detector_keywords("repair_service").fetch("keywords")
    end

    def normalize(text)
      text.to_s.downcase
        .unicode_normalize(:nfkd)
        .gsub(/[^\x00-\x7F]/, "")
    end
  end
end

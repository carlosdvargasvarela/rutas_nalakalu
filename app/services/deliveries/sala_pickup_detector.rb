# app/services/deliveries/sala_pickup_detector.rb
module Deliveries
  class SalaPickupDetector
    KEYWORDS = [
      "recoger de sala",
      "pendiente sp",
      "pendiente se",
      "pendiente sg",
      "\\bsp\\b",
      "\\bse\\b",
      "\\bsg\\b"
    ].freeze

    EXCLUSIONS = [
      "entregado en sala",
      "entregado en sp",
      "entregado en se",
      "entregado en sg",
      "entregado sp",
      "entregado se",
      "entregado sg"
    ].freeze

    SALA_MAP = {
      "SP" => "Sala Palmares",
      "SE" => "Sala Escazú",
      "SG" => "Sala Guanacaste"
    }.freeze

    def initialize(delivery)
      @delivery = delivery
    end

    def actionable_items
      return [] if @delivery.status.in?(%w[delivered rescheduled cancelled archived])

      @delivery.delivery_items.reject { |item|
        item.status.in?(%w[delivered rescheduled cancelled archived])
      }.select { |item|
        name = normalize(item.product.to_s)
        contains_keyword?(name) && !contains_exclusion?(name)
      }
    end

    def items_by_sala
      actionable_items.group_by { |item| detect_sala(item.product.to_s) }
    end

    private

    def normalize(text)
      text.downcase
        .unicode_normalize(:nfd)
        .gsub(/\p{Mn}/, "") # Elimina tildes
    end

    def contains_keyword?(name)
      KEYWORDS.any? { |kw| name.match?(/#{kw}/i) }
    end

    def contains_exclusion?(name)
      EXCLUSIONS.any? { |ex| name.match?(/#{Regexp.escape(ex)}/i) }
    end

    def detect_sala(name)
      n = normalize(name)
      return "SP" if n.match?(/\bsp\b/) || n.include?("palmares")
      return "SE" if n.match?(/\bse\b/) || n.include?("escazu")
      return "SG" if n.match?(/\bsg\b/) || n.include?("guanacaste")
      "SALA"
    end
  end
end

# app/services/deliveries/sala_pickup_detector.rb
module Deliveries
  class SalaPickupDetector
    # Códigos cortos: se verifican case-sensitive en texto original para evitar
    # confundir pronombres españoles ("se", "sp") con códigos de sala.
    CODE_PATTERN = /\b(SP|SE|SG)\b/.freeze

    PHRASE_KEYWORDS = [
      "recoger de sala",
      "pendiente sp",
      "pendiente se",
      "pendiente sg",
      "tienda"
    ].freeze

    EXCLUSIONS = [
      "entregado en sala",
      "entregado en sp",
      "entregado en se",
      "entregado en sg",
      "entregado sp",
      "entregado se",
      "entregado sg",
      "entregado en tienda",
      "entregado tienda"
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
        item.status.in?(%w[delivered rescheduled cancelled archived]) ||
        item.sala_pickup_requested?
      }.select { |item|
        name = item.product.to_s
        contains_keyword?(name) && !contains_exclusion?(normalize(name))
      }
    end

    def items_by_sala
      actionable_items.group_by { |item| detect_sala(item.product.to_s) }
    end

    private

    def normalize(text)
      text.downcase
        .unicode_normalize(:nfd)
        .gsub(/\p{Mn}/, "")
    end

    def contains_keyword?(original_name)
      original_name.match?(CODE_PATTERN) ||
        PHRASE_KEYWORDS.any? { |kw| normalize(original_name).include?(kw) }
    end

    def contains_exclusion?(normalized_name)
      EXCLUSIONS.any? { |ex| normalized_name.include?(ex) }
    end

    def detect_sala(name)
      n = normalize(name)
      return "SP" if name.match?(/\bSP\b/) || n.include?("palmares")
      return "SE" if name.match?(/\bSE\b/) || n.include?("escazu")
      return "SG" if name.match?(/\bSG\b/) || n.include?("guanacaste")
      "SALA"
    end
  end
end

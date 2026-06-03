module Deliveries
  # Inspects a delivery (or raw params) and determines whether it is a showroom
  # movement, and if so which showrooms are involved.
  #
  # Usage:
  #   result = ShowroomDetector.new(delivery: delivery).detect
  #   result[:is_showroom]            # => true / false
  #   result[:destination_showroom]   # => Showroom or nil
  #   result[:is_inter_showroom]      # => true if "entre salas" pattern matched
  class ShowroomDetector
    def initialize(delivery: nil, order_number: nil, address: nil, product_texts: [])
      @delivery       = delivery
      @order_number   = (order_number || delivery&.order&.number).to_s.strip
      @address        = (address || delivery&.delivery_address&.address.to_s + " " +
                          delivery&.delivery_address&.description.to_s).strip
      @product_texts  = product_texts.presence ||
                        delivery&.delivery_items&.map { |di| di.order_item&.product.to_s } || []
    end

    def detect
      showrooms = Showroom.includes(:delivery_address).all

      inter = detect_inter_showroom(showrooms)
      return inter if inter[:is_showroom]

      restock = detect_restock(showrooms)
      return restock if restock[:is_showroom]

      { is_showroom: false, destination_showroom: nil, is_inter_showroom: false }
    end

    private

    attr_reader :order_number, :address, :product_texts

    def detect_inter_showroom(showrooms)
      matched = showrooms.find do |sr|
        keywords = sr.inter_sala_keywords.map(&:downcase)
        keywords.any? { |kw| order_number.downcase.include?(kw) } ||
          keywords.any? { |kw| address.downcase.include?(kw) } ||
          product_texts.any? { |pt| keywords.any? { |kw| pt.downcase.include?(kw) } }
      end

      # Fallback: universal "entre salas" keyword even if no showroom matches
      fallback = matched.nil? &&
        order_number.downcase.include?("entre salas")

      if matched || fallback
        destination = matched || address_matched_showroom(showrooms)
        { is_showroom: true, destination_showroom: destination, is_inter_showroom: true }
      else
        { is_showroom: false, destination_showroom: nil, is_inter_showroom: false }
      end
    end

    def detect_restock(showrooms)
      prefix_matched = showrooms.find do |sr|
        sr.order_number_prefixes.any? { |p| order_number.start_with?(p) }
      end

      keyword_matched = prefix_matched.nil? && showrooms.find do |sr|
        kws = sr.order_number_keywords.map(&:downcase)
        kws.any? { |kw| order_number.downcase.include?(kw) }
      end

      product_matched = (prefix_matched || keyword_matched).nil? && showrooms.find do |sr|
        pkws = sr.product_keywords.map(&:downcase)
        product_texts.any? { |pt| pkws.any? { |kw| pt.downcase.include?(kw) } }
      end

      destination = prefix_matched || keyword_matched || product_matched ||
        address_matched_showroom(showrooms)

      if destination
        { is_showroom: true, destination_showroom: destination, is_inter_showroom: false }
      else
        { is_showroom: false, destination_showroom: nil, is_inter_showroom: false }
      end
    end

    def address_matched_showroom(showrooms)
      showrooms.find do |sr|
        next unless sr.delivery_address
        sr.delivery_address.id == @delivery&.delivery_address_id
      end
    end
  end
end

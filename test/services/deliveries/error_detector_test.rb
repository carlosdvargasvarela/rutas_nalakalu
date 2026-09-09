require "test_helper"

module Deliveries
  class ErrorDetectorTest < ActiveSupport::TestCase
    test "flags a delivery address stuck at the map's default pin, with the severity declared by the model" do
      delivery = deliveries(:one)
      delivery.delivery_address.update!(
        latitude: DeliveryAddress::DEFAULT_MAP_LAT,
        longitude: DeliveryAddress::DEFAULT_MAP_LNG
      )

      detector = ErrorDetector.new(delivery)
      finding = detector.errors.find { |e| e[:message].include?("Coordenadas no confirmadas") }

      assert finding
      assert_equal "high", finding[:severity]
    end

    test "flags over-delivery: delivered more than what was ordered" do
      delivery = deliveries(:one)
      delivery.delivery_items.first.update!(quantity_delivered: 99)

      detector = ErrorDetector.new(delivery)
      finding = detector.errors.find { |e| e[:message].include?("se entregó") }

      assert finding
      assert_match(/se entregó 99 pero se pidieron 1/, finding[:message])
    end

    test "product error names the item explicitly instead of a generic count" do
      delivery = deliveries(:one)
      delivery.delivery_items.first.update!(status: :cancelled)

      detector = ErrorDetector.new(delivery)
      finding = detector.errors.find { |e| e[:message].include?("estado") }

      assert finding
      assert_includes finding[:message], delivery.delivery_items.first.order_item.product
    end
  end
end

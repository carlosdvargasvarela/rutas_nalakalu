require "test_helper"

module Deliveries
  class SalaPickupDetectorTest < ActiveSupport::TestCase
    def detector_for(*product_names)
      delivery = Delivery.new(status: "scheduled")
      product_names.each do |name|
        delivery.delivery_items.build(
          order_item: OrderItem.new(product: name, quantity: 1),
          status: "pending",
          quantity_delivered: 1
        )
      end
      SalaPickupDetector.new(delivery)
    end

    test "detects standalone word tienda" do
      detector = detector_for("Mesa - pendiente retiro tienda")
      assert_equal 1, detector.actionable_items.size
    end

    test "detects tienda inside parentheses" do
      detector = detector_for("Silla (tienda)")
      assert_equal 1, detector.actionable_items.size
    end

    test "detects tienda combined with showroom name" do
      detector = detector_for("Sofa - Tienda Escazu")
      assert_equal 1, detector.actionable_items.size
    end

    test "excludes entregado en tienda phrasing" do
      detector = detector_for("Entregado en tienda")
      assert_equal 0, detector.actionable_items.size
    end

    test "excludes entregado tienda phrasing" do
      detector = detector_for("Entregado tienda")
      assert_equal 0, detector.actionable_items.size
    end

    test "does not false-positive on unrelated word containing similar letters" do
      detector = detector_for("Atiende pedido especial")
      assert_equal 0, detector.actionable_items.size
    end

    test "still detects existing sala phrase keyword" do
      detector = detector_for("Mesa pendiente sp")
      assert_equal 1, detector.actionable_items.size
    end

    test "tienda combined with city name groups under the matching sala code" do
      detector = detector_for("Tienda Escazu")
      assert_equal({"SE" => 1}, detector.items_by_sala.transform_values(&:size))
    end

    test "tienda Guanacaste groups under SG" do
      detector = detector_for("Tienda Guanacaste")
      assert_equal({"SG" => 1}, detector.items_by_sala.transform_values(&:size))
    end

    test "tienda Palmares groups under SP" do
      detector = detector_for("Tienda Palmares")
      assert_equal({"SP" => 1}, detector.items_by_sala.transform_values(&:size))
    end

    test "bare word sala does not trigger (common living-room furniture term)" do
      detector = detector_for("Juego de Sala 3 piezas")
      assert_equal 0, detector.actionable_items.size
    end
  end
end

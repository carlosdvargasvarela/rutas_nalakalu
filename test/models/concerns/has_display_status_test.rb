require "test_helper"

class HasDisplayStatusTest < ActiveSupport::TestCase
  test "translates a known status to its Spanish label" do
    assert_equal "En bodegaje", Delivery.new(status: :warehousing).display_status
  end

  test "falls back to humanize when the status has no entry in DISPLAY_STATUS_LABELS" do
    fake_model = Class.new do
      include HasDisplayStatus
      attr_accessor :status
    end
    fake_model.const_set(:DISPLAY_STATUS_LABELS, {"known" => "Conocido"}.freeze)

    instance = fake_model.new
    instance.status = "unmapped_status"

    assert_equal "Unmapped status", instance.display_status
  end

  test "every model including the concern defines DISPLAY_STATUS_LABELS" do
    [Delivery, DeliveryPlan, DeliveryPlanAssignment, DeliveryItem, Order, OrderItem].each do |model|
      assert model.const_defined?(:DISPLAY_STATUS_LABELS), "#{model} debe definir DISPLAY_STATUS_LABELS"
      assert model::DISPLAY_STATUS_LABELS.keys.all? { |k| model.statuses.key?(k) },
        "#{model}::DISPLAY_STATUS_LABELS tiene una clave que no es un status válido del enum"
    end
  end
end

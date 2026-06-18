require "test_helper"

class DeliveryFailureServiceTest < ActiveSupport::TestCase
  test "marks the delivery failed, clones it, and records a failed DeliveryEvent with the new delivery id" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    new_delivery = nil
    assert_difference -> { DeliveryEvent.where(action: "failed").count }, 1 do
      new_delivery = DeliveryFailureService.new(
        delivery, reason: "Cliente no se encontraba", failed_by: users(:one)
      ).call
    end

    event = DeliveryEvent.where(action: "failed").last
    assert_equal delivery.id, event.delivery_id
    assert_equal new_delivery.id, event.payload_data["new_delivery_id"]
    assert_equal users(:one).id, event.actor_id
  end

  test "item status changes during failure are visible in PaperTrail" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      DeliveryFailureService.new(delivery, reason: "test").call
    end
  end
end

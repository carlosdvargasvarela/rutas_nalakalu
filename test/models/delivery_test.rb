require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
  test "mark_all_loaded! leaves a PaperTrail version on each affected item" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(load_status: :unloaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      delivery.mark_all_loaded!
    end

    assert_equal "loaded", item.reload.load_status
  end

  test "reset_load_status! leaves a PaperTrail version on each affected item" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(load_status: :loaded)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      delivery.reset_load_status!
    end

    assert_equal "unloaded", item.reload.load_status
  end
end

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

  test "hidden_from_route_map? is true only for cancelled, rescheduled or archived deliveries" do
    delivery = deliveries(:one)

    %w[cancelled rescheduled archived].each do |status|
      delivery.status = status
      assert delivery.hidden_from_route_map?, "#{status} should be hidden from the route map"
    end

    %w[scheduled ready_to_deliver in_plan in_route delivered failed loaded_on_truck warehousing].each do |status|
      delivery.status = status
      refute delivery.hidden_from_route_map?, "#{status} should still show on the route map"
    end
  end

  test "calculate_delivery_status mixed terminal priority is (delivered = failed) > cancelled > rescheduled" do
    delivery = deliveries(:one)

    assert_equal :delivered, delivery.send(:calculate_delivery_status, %w[delivered rescheduled])
    assert_equal :delivered, delivery.send(:calculate_delivery_status, %w[delivered cancelled])
    assert_equal :delivered, delivery.send(:calculate_delivery_status, %w[delivered failed])
    assert_equal :failed, delivery.send(:calculate_delivery_status, %w[failed cancelled])
    assert_equal :failed, delivery.send(:calculate_delivery_status, %w[failed rescheduled])
    assert_equal :cancelled, delivery.send(:calculate_delivery_status, %w[cancelled rescheduled])
  end

  test "calculate_delivery_status active mix shows the least-advanced item until everything clears that stage" do
    # deliveries(:one) ya tiene delivery_plan_assignments(:one) -> delivery_plan.present? es true,
    # así que "confirmed" resuelve a :in_plan, no a :ready_to_deliver (ver test aparte sin plan).
    delivery = deliveries(:one)

    assert_equal :scheduled, delivery.send(:calculate_delivery_status, %w[pending in_route])
    assert_equal :scheduled, delivery.send(:calculate_delivery_status, %w[pending confirmed])
    assert_equal :in_plan, delivery.send(:calculate_delivery_status, %w[confirmed in_route])
    assert_equal :in_plan, delivery.send(:calculate_delivery_status, %w[confirmed loaded_on_truck])
    assert_equal :in_plan, delivery.send(:calculate_delivery_status, %w[in_plan in_route])
    assert_equal :in_plan, delivery.send(:calculate_delivery_status, %w[in_plan loaded_on_truck])
    assert_equal :loaded_on_truck, delivery.send(:calculate_delivery_status, %w[loaded_on_truck in_route])
    assert_equal :in_route, delivery.send(:calculate_delivery_status, %w[in_route in_route])
  end

  test "calculate_delivery_status confirmed resolves to ready_to_deliver when there is no real delivery_plan" do
    delivery = Delivery.new
    assert_not delivery.delivery_plan.present?

    assert_equal :ready_to_deliver, delivery.send(:calculate_delivery_status, %w[confirmed in_route])
    assert_equal :ready_to_deliver, delivery.send(:calculate_delivery_status, %w[confirmed loaded_on_truck])
  end

  test "calculate_delivery_status treats warehousing as tied with loaded_on_truck and never returns :warehousing" do
    delivery = deliveries(:one)

    assert_equal :loaded_on_truck, delivery.send(:calculate_delivery_status, %w[warehousing in_route])
    assert_equal :loaded_on_truck, delivery.send(:calculate_delivery_status, %w[loaded_on_truck warehousing])
  end

  test "calculate_delivery_status ignores terminal items entirely once an active item exists" do
    delivery = Delivery.new
    assert_not delivery.delivery_plan.present?

    assert_equal :scheduled, delivery.send(:calculate_delivery_status, %w[delivered pending])
    assert_equal :in_route, delivery.send(:calculate_delivery_status, %w[delivered in_route])
    assert_equal :ready_to_deliver, delivery.send(:calculate_delivery_status, %w[cancelled confirmed])
  end

  test "default_item_status maps the delivery's current level to the matching item status" do
    delivery = deliveries(:one)

    {
      "scheduled" => "pending",
      "ready_to_deliver" => "confirmed",
      "in_plan" => "in_plan",
      "loaded_on_truck" => "loaded_on_truck",
      "warehousing" => "warehousing",
      "in_route" => "in_route"
    }.each do |delivery_status, expected_item_status|
      delivery.status = delivery_status
      assert_equal expected_item_status, delivery.default_item_status, "for delivery status #{delivery_status}"
    end
  end

  test "default_item_status falls back to pending for terminal delivery statuses" do
    delivery = deliveries(:one)

    %w[delivered cancelled rescheduled archived failed].each do |delivery_status|
      delivery.status = delivery_status
      assert_equal "pending", delivery.default_item_status, "for delivery status #{delivery_status}"
    end
  end

  test "visible_in_plan_for? is true for the 6-status allowlist for any user, and only admin for the rest" do
    delivery = deliveries(:one)
    seller = User.new(role: "seller")
    admin = User.new(role: "admin")

    %w[scheduled ready_to_deliver in_plan in_route delivered loaded_on_truck].each do |status|
      delivery.status = status
      assert delivery.visible_in_plan_for?(seller), "#{status} debería ser visible para seller"
      assert delivery.visible_in_plan_for?(admin), "#{status} debería ser visible para admin"
    end

    %w[cancelled archived rescheduled failed warehousing].each do |status|
      delivery.status = status
      refute delivery.visible_in_plan_for?(seller), "#{status} NO debería ser visible para seller"
      assert delivery.visible_in_plan_for?(admin), "#{status} debería seguir siendo visible para admin"
    end
  end

  test "visible_in_plan_for? treats a nil user like a non-admin" do
    delivery = deliveries(:one)
    delivery.status = "cancelled"
    refute delivery.visible_in_plan_for?(nil)
  end

  test "items_visible_in_plan without a user filters to the 6-status allowlist" do
    delivery = deliveries(:one)
    item = delivery.delivery_items.first
    item.update_columns(status: DeliveryItem.statuses["cancelled"])

    refute delivery.items_visible_in_plan.exists?(item.id)
  end

  test "items_visible_in_plan for an admin user returns every item regardless of status" do
    delivery = deliveries(:one)
    item = delivery.delivery_items.first
    item.update_columns(status: DeliveryItem.statuses["cancelled"])
    admin = User.new(role: "admin")

    assert_includes delivery.items_visible_in_plan(admin), item
  end
end

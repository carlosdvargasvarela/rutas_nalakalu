require "test_helper"

class DeliveryItemTest < ActiveSupport::TestCase
  test "eligible_for_plan_for_others excludes cancelled, failed, warehousing and rescheduled — not just rescheduled" do
    item = delivery_items(:one)

    %w[cancelled failed warehousing rescheduled].each do |status|
      item.update_columns(status: DeliveryItem.statuses[status])
      refute DeliveryItem.eligible_for_plan_for_others.exists?(item.id),
        "esperaba que status=#{status} quedara excluido de eligible_for_plan_for_others"
    end

    %w[pending confirmed in_plan in_route delivered loaded_on_truck].each do |status|
      item.update_columns(status: DeliveryItem.statuses[status])
      assert DeliveryItem.eligible_for_plan_for_others.exists?(item.id),
        "esperaba que status=#{status} quedara incluido en eligible_for_plan_for_others"
    end
  end

  test "visible_to_all? matches the same 6-status allowlist as the scope" do
    item = delivery_items(:one)

    item.update_columns(status: DeliveryItem.statuses["cancelled"])
    refute item.reload.visible_to_all?

    item.update_columns(status: DeliveryItem.statuses["in_route"])
    assert item.reload.visible_to_all?
  end
end

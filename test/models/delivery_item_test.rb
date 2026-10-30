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

  test "statuses_hidden_by_default hides nothing when the list would end up empty" do
    assert_equal %w[Reprogramado Archivado], DeliveryItem.statuses_hidden_by_default(%w[Confirmado Archivado])
    assert_empty DeliveryItem.statuses_hidden_by_default(%w[Reprogramado Archivado])
  end

  test "by_product ignores case, accents and edge spaces" do
    delivery = delivery_items(:one).delivery
    delivery.delivery_items.destroy_all
    ["zócalo", " Ábaco", "Mesa", "alfombra"].each do |name|
      order_item = delivery.order.order_items.create!(product: name, quantity: 1)
      delivery.delivery_items.create!(order_item: order_item, quantity_delivered: 1)
    end

    assert_equal [" Ábaco", "alfombra", "Mesa", "zócalo"],
      delivery.delivery_items.by_product.map(&:product)
  end
end

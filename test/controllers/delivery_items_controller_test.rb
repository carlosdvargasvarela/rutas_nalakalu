require "test_helper"

class DeliveryItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "bulk_reschedule merges into an existing delivery for the same order/address/date" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :confirmed)
    new_date = delivery.delivery_date + 5.days
    existing_target = Delivery.create!(
      order: delivery.order,
      delivery_address: delivery.delivery_address,
      delivery_date: new_date,
      status: :scheduled
    )

    patch bulk_reschedule_delivery_items_url, params: {
      delivery_id: delivery.id,
      item_ids: item.id.to_s,
      new_delivery: "true",
      new_date: new_date.to_s
    }, as: :turbo_stream

    assert_response :success
    assert_equal "rescheduled", item.reload.status
    assert_includes existing_target.delivery_items.reload.pluck(:order_item_id), item.order_item_id
    assert_equal 1, Delivery.where(order_id: delivery.order_id, delivery_address_id: delivery.delivery_address_id, delivery_date: new_date).count
  end

  test "admin can undo a delivered item, returning it to confirmed" do
    item = delivery_items(:one)
    item.update!(status: :delivered)

    patch undo_delivered_delivery_item_url(item), as: :turbo_stream

    assert_response :success
    assert_equal "confirmed", item.reload.status
  end

  test "undo_delivered is rejected for a non-admin user" do
    seller = users(:two)
    seller.update!(role: :seller, force_password_change: false)
    sign_out @admin
    sign_in seller

    item = delivery_items(:one)
    item.update!(status: :delivered)

    patch undo_delivered_delivery_item_url(item), as: :turbo_stream

    assert_equal "delivered", item.reload.status
  end

  test "undo_delivered is rejected when the item is not delivered" do
    item = delivery_items(:one)
    item.update!(status: :confirmed)

    patch undo_delivered_delivery_item_url(item), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "confirmed", item.reload.status
  end

  test "admin can archive and unarchive an item; archived items don't count for the delivery status" do
    delivery = deliveries(:one)
    item = delivery_items(:one)
    item.update!(status: :pending)

    assert_difference -> { delivery.delivery_events.where(action: "item_archived").count }, 1 do
      patch archive_delivery_item_url(item), as: :turbo_stream
    end
    assert_response :success
    assert_equal "archived", item.reload.status
    assert_not_includes DeliveryItem.eligible_for_plan, item
    assert_not item.bulk_actionable?
    assert_not_includes delivery.delivery_items.not_archived, item

    patch unarchive_delivery_item_url(item), as: :turbo_stream
    assert_response :success
    assert_equal "pending", item.reload.status
  end

  test "archiving the only pending item lets the delivery move on with the remaining items" do
    delivery = deliveries(:one)
    delivery.delivery_items.destroy_all
    done = delivery.delivery_items.create!(order_item: delivery.order.order_items.create!(product: "A", quantity: 1, status: :ready), quantity_delivered: 1, status: :delivered)
    extra = delivery.delivery_items.create!(order_item: delivery.order.order_items.create!(product: "B", quantity: 1, status: :ready), quantity_delivered: 1, status: :pending)
    assert_equal "scheduled", delivery.reload.status

    patch archive_delivery_item_url(extra), as: :turbo_stream

    assert_equal "delivered", delivery.reload.status
    assert_equal done.quantity_delivered, delivery.total_items
  end

  test "archiving a delivered item is rejected" do
    item = delivery_items(:one)
    item.update!(status: :delivered)

    patch archive_delivery_item_url(item), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "delivered", item.reload.status
  end

  test "non-admin cannot archive an item" do
    @admin.update!(role: :logistics)
    item = delivery_items(:one)
    item.update!(status: :pending)

    patch archive_delivery_item_url(item), as: :turbo_stream

    assert_not_equal "archived", item.reload.status
  end

  test "archived items are excluded from the API payload, mark_as_delivered and the failure clone" do
    delivery = deliveries(:one)
    delivery.delivery_items.destroy_all
    keep = delivery.delivery_items.create!(order_item: delivery.order.order_items.create!(product: "Keep", quantity: 1, status: :ready), quantity_delivered: 1, status: :confirmed)
    gone = delivery.delivery_items.create!(order_item: delivery.order.order_items.create!(product: "Gone", quantity: 1, status: :ready), quantity_delivered: 1, status: :archived)

    get api_v1_deliveries_url, as: :json
    products = JSON.parse(response.body).to_s
    assert_includes products, "Keep"
    assert_not_includes products, "Gone"

    delivery.mark_as_delivered!
    assert_equal "delivered", delivery.reload.status
    assert_equal "archived", gone.reload.status
    assert_equal "delivered", keep.reload.status
  end
end

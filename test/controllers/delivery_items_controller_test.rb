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
end

require "test_helper"

class DeliveryUpdateStreamSmokeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "update renders turbo_stream with detail and card" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    delivery = deliveries(:one)
    patch delivery_url(delivery), params: {
      delivery: {
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        contact_name: delivery.contact_name,
        contact_phone: delivery.contact_phone
      }
    }, as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_includes response.body, dom_id(delivery, :card)
    assert_includes response.body, dom_id(delivery, :detail)
  end

  test "mark_as_delivered renders turbo_stream with product table" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    delivery = deliveries(:one)
    patch mark_as_delivered_delivery_url(delivery), as: :turbo_stream
    assert_response :success
    assert_includes response.body, "delivery_items_list"
  end
end

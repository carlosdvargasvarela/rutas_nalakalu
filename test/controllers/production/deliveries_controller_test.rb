require "test_helper"

class Production::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @delivery = deliveries(:one)
    @delivered_item = delivery_items(:one)
    @delivered_item.update!(status: :delivered)

    pending_order_item = order_items(:one).dup.tap { |oi| oi.product = "Silla pendiente" }
    pending_order_item.order = @delivery.order
    pending_order_item.save!
    @pending_item = @delivery.delivery_items.create!(
      order_item: pending_order_item,
      quantity_delivered: 1,
      status: :pending
    )

    @user = users(:one)
    @user.update!(role: :logistics, email: "logistica@test.com",
      password: "password123", password_confirmation: "password123")
    sign_in @user
  end

  test "reschedule_delivery only moves active items and leaves the original delivered when its other items already were" do
    patch reschedule_delivery_production_delivery_path(@delivery), params: {new_date: (Date.current + 7).to_s}

    assert_response :redirect
    assert_equal "delivered", @delivery.reload.status
    assert_equal "rescheduled", @pending_item.reload.status
    assert_equal "delivered", @delivered_item.reload.status

    new_delivery = Delivery.order(created_at: :desc).first
    assert_equal "scheduled", new_delivery.status
    assert_equal [@pending_item.order_item_id], new_delivery.delivery_items.pluck(:order_item_id)
  end

  test "reschedule_delivery requires a new date" do
    patch reschedule_delivery_production_delivery_path(@delivery), params: {new_date: ""}

    assert_response :redirect
    assert_match(/reagendar/i, flash[:alert])
  end

  test "add_product makes the new item enter at the delivery's current level instead of always pending" do
    @pending_item.update!(status: :in_plan)
    @delivery.update_column(:status, :in_plan)

    post add_product_production_delivery_path(@delivery),
      params: {product: "Lámpara nueva", quantity: 1, quantity_delivered: 1}

    assert_response :redirect
    new_item = @delivery.delivery_items.order(created_at: :desc).first
    assert_equal "in_plan", new_item.status
    assert_equal "in_plan", @delivery.reload.status
  end
end

require "test_helper"

module Deliveries
  class ReschedulerTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
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
    end

    test "rescheduling a delivery whose other items are already delivered leaves it as delivered, not rescheduled" do
      Rescheduler.new(delivery: @delivery, new_date: Date.current + 7, current_user: @user).call

      assert_equal "delivered", @delivery.reload.status
    end

    test "only active items move to the new delivery; already-delivered items stay put" do
      rescheduler = Rescheduler.new(delivery: @delivery, new_date: Date.current + 7, current_user: @user)
      target = rescheduler.call

      assert_equal "scheduled", target.status
      assert_equal [@pending_item.order_item_id], target.delivery_items.pluck(:order_item_id)
      assert_equal "rescheduled", @pending_item.reload.status
      assert_equal "delivered", @delivered_item.reload.status
    end

    test "a delivery with no items already delivered still ends up rescheduled" do
      @delivered_item.update!(status: :pending)

      Rescheduler.new(delivery: @delivery, new_date: Date.current + 7, current_user: @user).call

      assert_equal "rescheduled", @delivery.reload.status
    end
  end
end

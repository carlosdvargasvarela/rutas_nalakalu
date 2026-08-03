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

    test "reschedules into an existing delivery for the same order/address/date instead of creating a duplicate" do
      new_date = Date.current + 7
      existing_target = Delivery.create!(
        order: @delivery.order,
        delivery_address: @delivery.delivery_address,
        delivery_date: new_date,
        status: :scheduled
      )
      other_order_item = order_items(:one).dup.tap { |oi| oi.product = "Mesa ya en destino" }
      other_order_item.order = @delivery.order
      other_order_item.save!
      existing_item = existing_target.delivery_items.create!(
        order_item: other_order_item,
        quantity_delivered: 2,
        status: :pending
      )

      target = Rescheduler.new(delivery: @delivery, new_date: new_date, current_user: @user).call

      assert_equal existing_target.id, target.id
      assert_equal 1, Delivery.where(order_id: @delivery.order_id, delivery_address_id: @delivery.delivery_address_id, delivery_date: new_date).count
      assert_includes target.delivery_items.pluck(:order_item_id), @pending_item.order_item_id
      assert_equal 2, existing_item.reload.quantity_delivered
    end

    test "merges quantities when the existing target delivery already has an item for the same order_item" do
      new_date = Date.current + 7
      existing_target = Delivery.create!(
        order: @delivery.order,
        delivery_address: @delivery.delivery_address,
        delivery_date: new_date,
        status: :scheduled
      )
      existing_item = existing_target.delivery_items.create!(
        order_item: @pending_item.order_item,
        quantity_delivered: 3,
        status: :pending
      )

      Rescheduler.new(delivery: @delivery, new_date: new_date, current_user: @user).call

      assert_equal 4, existing_item.reload.quantity_delivered
      assert_equal "rescheduled", @pending_item.reload.status
    end
  end
end

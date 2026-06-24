require "test_helper"

module DeliveryItems
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

    test "rescheduling the last active item leaves the delivery as delivered when its siblings are already delivered" do
      Rescheduler.new(
        delivery_item: @pending_item,
        params: {new_delivery: "true", new_date: (Date.current + 7).to_s},
        current_user: @user,
        notify: false
      ).call

      assert_equal "delivered", @delivery.reload.status
    end

    test "the new target delivery is scheduled and holds the rescheduled item" do
      rescheduler = Rescheduler.new(
        delivery_item: @pending_item,
        params: {new_delivery: "true", new_date: (Date.current + 7).to_s},
        current_user: @user,
        notify: false
      )
      rescheduler.call

      target = rescheduler.target_delivery
      assert_not_equal @delivery.id, target.id
      assert_equal "scheduled", target.status
      assert_equal "rescheduled", @pending_item.reload.status
    end
  end
end

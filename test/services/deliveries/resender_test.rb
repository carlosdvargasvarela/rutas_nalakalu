require "test_helper"

module Deliveries
  class ResenderTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @delivery = deliveries(:one)
      delivery_items(:one).update!(status: :delivered)
      @delivery.reload.update_status_based_on_items
    end

    test "creates a new delivery with the same products and leaves the original delivered, repeatable" do
      first = Resender.new(delivery: @delivery, new_date: Date.current + 3, current_user: @user, reason: "Flotilla 2").call
      second = Resender.new(delivery: @delivery, new_date: Date.current + 10, current_user: @user).call

      assert_equal "delivered", @delivery.reload.status
      [first, second].each do |target|
        assert_not_equal @delivery.id, target.id
        assert_equal @delivery.delivery_address_id, target.delivery_address_id
        assert_equal [delivery_items(:one).order_item_id], target.delivery_items.pluck(:order_item_id)
        assert_not target.delivery_items.first.delivered?
      end
      assert_equal "Flotilla 2", @delivery.delivery_events.where(action: "resent").first.payload_data["reason"]
    end

    test "only the chosen products are resent" do
      other_oi = order_items(:one).dup.tap { |oi| oi.product = "Silla extra"; oi.order = @delivery.order }
      other_oi.save!
      @delivery.delivery_items.create!(order_item: other_oi, quantity_delivered: 2, status: :delivered)

      target = Resender.new(delivery: @delivery, new_date: Date.current + 3, current_user: @user,
        item_ids: [delivery_items(:one).id]).call
      assert_equal [delivery_items(:one).order_item_id], target.delivery_items.pluck(:order_item_id)

      assert_raises(ArgumentError) { Resender.new(delivery: @delivery, new_date: Date.current + 3, current_user: @user, item_ids: []).call }
    end

    test "refuses deliveries that are not delivered or cancelled" do
      delivery_items(:one).update!(status: :pending)
      @delivery.reload.update_status_based_on_items
      assert_raises(ArgumentError) { Resender.new(delivery: @delivery, new_date: Date.current + 3, current_user: @user).call }
    end
  end
end

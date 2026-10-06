require "test_helper"

module Deliveries
  class InternalCreatorTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @params = ActionController::Parameters.new(
        delivery: {
          delivery_date: Date.current,
          contact_name: "Chofer",
          contact_phone: "0000-0000",
          delivery_items_attributes: {
            "0" => {
              order_item_attributes: {
                product: "10 cajas de tornillos 2\"\n5 rollos de cinta de embalaje\n\n  \nGuantes"
              }
            }
          }
        },
        delivery_address: {
          address: "Calle Falsa 123"
        }
      )
    end

    test "creates one order item per non-blank product line" do
      delivery = InternalCreator.new(params: @params, current_user: @user).call

      assert_equal 3, delivery.delivery_items.count
      assert_equal(
        ["10 cajas de tornillos 2\"", "5 rollos de cinta de embalaje", "Guantes"],
        delivery.order.order_items.order(:id).pluck(:product)
      )
    end

    test "uses the submitted quantity (min 1) for the product" do
      @params[:delivery][:delivery_items_attributes] = {
        "0" => {order_item_attributes: {product: "Tornillos", quantity: "12"}},
        "1" => {order_item_attributes: {product: "Cinta", quantity: "0"}}
      }
      delivery = InternalCreator.new(params: @params, current_user: @user).call

      assert_equal [12, 1], delivery.delivery_items.order(:id).map(&:quantity_delivered)
      assert_equal [12, 1], delivery.order.order_items.order(:id).pluck(:quantity)
    end

    test "non-admin must pick a vendor" do
      @user.update!(role: :logistics)
      assert_raises(ArgumentError) { InternalCreator.new(params: @params, current_user: @user).call }
    end

    test "non-admin must add a product" do
      @user.update!(role: :logistics)
      @params[:vendor_address_id] = "1"
      @params[:delivery][:delivery_items_attributes] = {"0" => {order_item_attributes: {product: " "}}}
      assert_raises(ArgumentError) { InternalCreator.new(params: @params, current_user: @user).call }
    end

    test "non-admin cannot set delivery_notes" do
      @user.update!(role: :logistics)
      @params[:vendor_address_id] = "1"
      @params[:delivery][:delivery_notes] = "nota"
      delivery = InternalCreator.new(params: @params, current_user: @user).call
      assert_nil delivery.delivery_notes
    end
  end
end

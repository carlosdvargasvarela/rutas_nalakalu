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
  end
end

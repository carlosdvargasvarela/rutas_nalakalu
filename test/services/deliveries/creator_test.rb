require "test_helper"

class Deliveries::CreatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "creates delivery with a brand new client, order and address" do
    params = ActionController::Parameters.new(
      client: { name: "Cliente Nuevo Test", phone: "8888-0000", email: "" },
      order: { number: "PED-NEW-001" },
      seller_id: sellers(:one).id,
      delivery_address: {
        address: "Calle Falsa 123",
        description: "Casa azul, portón blanco",
        latitude: "9.9281",
        longitude: "-84.0907",
        plus_code: ""
      },
      delivery: {
        delivery_date: Date.current.to_s,
        delivery_address_id: "__new__",
        order_id: "__new__",
        contact_name: "Contacto Test",
        contact_phone: "8888-1111",
        delivery_time_preference: "Mañana",
        delivery_items_attributes: {
          "0" => {
            order_item_attributes: { product: "Sofa", quantity: "1" },
            quantity_delivered: "1"
          }
        }
      }
    )

    assert_difference [ "Client.count", "Order.count", "DeliveryAddress.count", "Delivery.count" ], 1 do
      Deliveries::Creator.new(params: params, current_user: @user).call
    end
  end
end

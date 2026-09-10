require "test_helper"

class DeliveryCreateErrorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "create re-renders :new without crashing when the delivery fails to save, sanitizing __new__ address/order" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    client = clients(:one)

    post deliveries_url, params: {
      client_id: client.id,
      delivery: {
        delivery_date: Date.current,
        delivery_address_id: "__new__",
        order_id: "__new__",
        contact_name: "Test",
        contact_phone: "8888-8888",
        delivery_items_attributes: {
          "0" => {
            quantity_delivered: 1,
            order_item_attributes: {product: "", quantity: 1} # producto en blanco -> falla la validación
          }
        }
      }
    }

    assert_response :unprocessable_entity
    assert_select "body" # renderizó :new sin explotar con un 500
  end
end

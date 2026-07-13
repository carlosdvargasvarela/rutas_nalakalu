require "test_helper"

class DeliveriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "should get index" do
    get deliveries_url
    assert_response :success
  end

  test "should get show" do
    get delivery_url(deliveries(:one))
    assert_response :success
  end

  test "production_manager gets the map/autocomplete address form for new_internal_delivery" do
    @admin.update!(role: :production_manager)
    get new_internal_delivery_deliveries_url
    assert_response :success
    assert_select "[data-controller=address-autocomplete]"
  end

  test "proveeduria gets the vendor select form for new_internal_delivery" do
    @admin.update!(role: :proveeduria)
    get new_internal_delivery_deliveries_url
    assert_response :success
    assert_select "[data-controller=vendor-address-select]"
  end

  test "update handles a duplicate-product validation failure without crashing on _return_to_panel" do
    delivery = deliveries(:one)
    order = delivery.order
    delivery_item = delivery_items(:one)
    order_item = order_items(:one)
    other_item = order.order_items.create!(product: "Ya existe", quantity: 1, status: :in_production)

    patch delivery_url(delivery), params: {
      delivery: {
        order_id: order.id,
        delivery_address_id: delivery.delivery_address_id,
        _return_to_panel: "1",
        delivery_items_attributes: {
          "0" => {
            id: delivery_item.id,
            order_item_id: order_item.id,
            quantity_delivered: delivery_item.quantity_delivered,
            order_item_attributes: {
              id: order_item.id,
              product: other_item.product,
              quantity: order_item.quantity
            }
          }
        }
      }
    }

    assert_response :unprocessable_entity
    assert_select "body" # rendered the edit view, didn't blow up with a 500
  end
end

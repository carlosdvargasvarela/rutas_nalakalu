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

  test "should get reschedule_form" do
    get reschedule_form_delivery_url(deliveries(:one))
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

  test "update rejects a direct delivery_date change, must go through reschedule_all" do
    delivery = deliveries(:one)
    original_date = delivery.delivery_date

    patch delivery_url(delivery), params: {
      delivery: {
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        delivery_date: (original_date + 3.days).to_s
      }
    }

    assert_response :unprocessable_entity
    assert_equal original_date, delivery.reload.delivery_date
  end

  test "update saves pending changes then reschedules and redirects to edit the rescheduled delivery" do
    delivery = deliveries(:one)
    original_date = delivery.delivery_date
    new_date = original_date + 5.days

    patch delivery_url(delivery), params: {
      delivery: {
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        contact_name: "Nuevo contacto de prueba",
        reschedule_new_date: new_date.to_s,
        reschedule_reason: "Cliente pidió otra fecha"
      }
    }

    target_delivery = Delivery.find_by(order_id: delivery.order_id, delivery_address_id: delivery.delivery_address_id, delivery_date: new_date)
    assert_not_nil target_delivery
    assert_redirected_to edit_delivery_path(target_delivery)

    assert_equal "Nuevo contacto de prueba", delivery.reload.contact_name
    assert_equal original_date, delivery.delivery_date
  end

  test "update reschedule merges into an existing delivery for the same order/address/date" do
    delivery = deliveries(:one)
    new_date = delivery.delivery_date + 5.days
    existing_target = Delivery.create!(
      order: delivery.order,
      delivery_address: delivery.delivery_address,
      delivery_date: new_date,
      status: :scheduled
    )

    patch delivery_url(delivery), params: {
      delivery: {
        order_id: delivery.order_id,
        delivery_address_id: delivery.delivery_address_id,
        reschedule_new_date: new_date.to_s
      }
    }

    assert_redirected_to edit_delivery_path(existing_target)
    assert_equal 1, Delivery.where(order_id: delivery.order_id, delivery_address_id: delivery.delivery_address_id, delivery_date: new_date).count
  end

  test "reschedule_all merges into an existing delivery for the same order/address/date" do
    delivery = deliveries(:one)
    new_date = delivery.delivery_date + 5.days
    existing_target = Delivery.create!(
      order: delivery.order,
      delivery_address: delivery.delivery_address,
      delivery_date: new_date,
      status: :scheduled
    )

    patch reschedule_all_delivery_url(delivery), params: {new_date: new_date.to_s}

    assert_redirected_to delivery_path(existing_target)
    assert_equal 1, Delivery.where(order_id: delivery.order_id, delivery_address_id: delivery.delivery_address_id, delivery_date: new_date).count
  end
end

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
end

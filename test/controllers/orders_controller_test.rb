require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "should get index" do
    get orders_url
    assert_response :success
  end

  test "should get show" do
    get order_url(orders(:one))
    assert_response :success
  end
end

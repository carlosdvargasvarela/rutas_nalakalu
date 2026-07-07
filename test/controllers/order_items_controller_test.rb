require "test_helper"

class OrderItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "should get confirm" do
    patch confirm_order_item_url(order_items(:one))
    assert_redirected_to orders_path
  end
end

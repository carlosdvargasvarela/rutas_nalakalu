require "test_helper"

class OrderItemsControllerTest < ActionDispatch::IntegrationTest
  test "should get confirm" do
    get order_items_confirm_url
    assert_response :success
  end
end

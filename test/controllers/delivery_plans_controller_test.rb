require "test_helper"

class DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get delivery_plans_new_url
    assert_response :success
  end

  test "should get create" do
    get delivery_plans_create_url
    assert_response :success
  end
end

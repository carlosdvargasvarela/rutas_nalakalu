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
end

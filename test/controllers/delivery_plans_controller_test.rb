require "test_helper"

class DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "should get new" do
    get new_delivery_plan_url
    assert_response :success
  end

  test "should get create" do
    post delivery_plans_url, params: {
      delivery_plan: {status: :draft},
      delivery_ids: [deliveries(:one).id]
    }
    assert_redirected_to edit_delivery_plan_path(DeliveryPlan.last)
  end
end

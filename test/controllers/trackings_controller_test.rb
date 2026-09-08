require "test_helper"

class TrackingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "seller can see the fleet tracking dashboard" do
    seller = users(:one)
    seller.update!(role: :seller, force_password_change: false)
    sign_in seller

    get tracking_url
    assert_response :success
  end

  test "driver is redirected away from the fleet tracking dashboard" do
    driver = users(:one)
    driver.update!(role: :driver, force_password_change: false)
    sign_in driver

    get tracking_url
    assert_redirected_to root_url
  end

  test "index only includes active plans" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    active_plan = delivery_plans(:plan_for_driver)
    active_plan.update_columns(status: DeliveryPlan.statuses[:routes_created])
    draft_plan = delivery_plans(:one)
    draft_plan.update_columns(status: DeliveryPlan.statuses[:draft])

    get tracking_url
    assert_response :success
    assert_match active_plan.id.to_s, response.body
    refute_match(/"id":#{draft_plan.id}[,}]/, response.body)
  end
end

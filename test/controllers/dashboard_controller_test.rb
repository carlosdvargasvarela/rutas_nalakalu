require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "loads successfully" do
    get root_url
    assert_response :success
  end

  test "attention queue lists a delivery within range that has address errors" do
    delivery = deliveries(:one)
    delivery.update_columns(delivery_date: Date.current, approved: true)

    get root_url
    assert_response :success
    assert_select "table td a", text: delivery.order.number
  end

  test "category filter excludes deliveries that don't match" do
    delivery = deliveries(:one)
    delivery.update_columns(delivery_date: Date.current, approved: true)

    get root_url(category: "warehousing")
    assert_response :success
    assert_select "table td a", {text: delivery.order.number, count: 0}
  end

  test "driver is redirected to their delivery plans" do
    driver = users(:one)
    driver.update!(role: :driver, force_password_change: false)
    sign_in driver

    get root_url
    assert_redirected_to driver_delivery_plans_path
  end
end

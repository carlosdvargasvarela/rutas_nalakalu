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

    # show_all=1 para no depender de la fecha de las entregas del fixture.
    get tracking_url(show_all: 1)
    assert_response :success
    # El JSON va dentro de un atributo HTML, así que Rails escapa las comillas.
    assert_match(/&quot;id&quot;:#{active_plan.id}[,}]/, response.body)
    refute_match(/&quot;id&quot;:#{draft_plan.id}[,}]/, response.body)
  end

  test "index defaults to today's plans and excludes active plans from other dates" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    today_plan = delivery_plans(:plan_for_driver)
    today_plan.update_columns(status: DeliveryPlan.statuses[:routes_created])
    today_plan.deliveries.update_all(delivery_date: Date.current)

    other_day_plan = delivery_plans(:one)
    other_day_plan.update_columns(status: DeliveryPlan.statuses[:routes_created])

    get tracking_url
    assert_response :success
    assert_match(/&quot;id&quot;:#{today_plan.id}[,}]/, response.body)
    refute_match(/&quot;id&quot;:#{other_day_plan.id}[,}]/, response.body)
  end

  test "index hides completed plans by default but shows them with status=completed or status=all" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    completed_plan = delivery_plans(:plan_for_driver)
    completed_plan.update_columns(status: DeliveryPlan.statuses[:completed])

    get tracking_url(show_all: 1)
    assert_response :success
    refute_match(/&quot;id&quot;:#{completed_plan.id}[,}]/, response.body)

    get tracking_url(show_all: 1, status: "completed")
    assert_response :success
    assert_match(/&quot;id&quot;:#{completed_plan.id}[,}]/, response.body)

    get tracking_url(show_all: 1, status: "all")
    assert_response :success
    assert_match(/&quot;id&quot;:#{completed_plan.id}[,}]/, response.body)
  end

  test "route works for a completed plan so its history stays visible after finishing" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    plan = delivery_plans(:plan_for_driver)
    plan.update_columns(status: DeliveryPlan.statuses[:completed])
    plan.delivery_plan_locations.create!(latitude: 9.9, longitude: -84.0, captured_at: 1.hour.ago, source: "batch")

    get tracking_route_url(plan)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).size
  end

  test "route returns ordered GPS pings for a plan" do
    admin = users(:one)
    admin.update!(role: :admin, force_password_change: false)
    sign_in admin

    plan = delivery_plans(:plan_for_driver)
    plan.delivery_plan_locations.create!(latitude: 9.91, longitude: -84.01, captured_at: 1.hour.ago, source: "batch")
    plan.delivery_plan_locations.create!(latitude: 9.9, longitude: -84.0, captured_at: 2.hours.ago, source: "batch")

    get tracking_route_url(plan)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body.size
    # Insertados en orden inverso a propósito: confirma que la respuesta
    # viene ordenada por captured_at ascendente, no por id de inserción.
    assert_equal [9.9, 9.91], body.map { |p| p["lat"] }
  end

  test "route is forbidden for drivers" do
    driver = users(:one)
    driver.update!(role: :driver, force_password_change: false)
    sign_in driver

    plan = delivery_plans(:plan_for_driver)
    get tracking_route_url(plan)
    assert_redirected_to root_url
  end
end

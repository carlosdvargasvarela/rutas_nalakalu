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

  test "send_to_logistics rechaza un plan sin paradas" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft], driver_id: users(:one).id)
    plan.delivery_plan_assignments.destroy_all

    patch send_to_logistics_delivery_plan_url(plan)

    assert_redirected_to edit_delivery_plan_path(plan)
    assert_equal "draft", plan.reload.status
    follow_redirect!
    assert_match "al menos una parada", response.body
  end

  test "send_to_logistics funciona con conductor y al menos una parada" do
    plan = delivery_plans(:one)
    plan.update_columns(status: DeliveryPlan.statuses[:draft], driver_id: users(:one).id)

    patch send_to_logistics_delivery_plan_url(plan)

    assert_redirected_to delivery_plan_path(plan)
    assert_equal "routes_created", plan.reload.status
  end

  test "show hides a cancelled delivery from a non-admin but keeps it visible for admin" do
    plan = delivery_plans(:one)
    delivery = delivery_plan_assignments(:one).delivery
    delivery.update_columns(status: Delivery.statuses[:cancelled])
    delivery_marker = "productosEntrega#{delivery.id}"

    sign_out @admin
    seller = users(:two)
    seller.update!(role: :seller, force_password_change: false)
    sign_in seller

    get delivery_plan_url(plan)
    assert_response :success
    refute_match delivery_marker, response.body

    sign_out seller
    sign_in @admin

    get delivery_plan_url(plan)
    assert_response :success
    assert_match delivery_marker, response.body
    assert_match "Cancelad", response.body
  end

  test "show hides a cancelled product from a non-admin but keeps it visible (flagged) for admin" do
    plan = delivery_plans(:one)
    item = delivery_plan_assignments(:one).delivery.delivery_items.first
    item.update_columns(status: DeliveryItem.statuses[:cancelled])
    item.order_item.update_columns(product: "PRODUCTO-UNICO-TEST-123")

    get delivery_plan_url(plan)
    assert_response :success
    assert_match "PRODUCTO-UNICO-TEST-123", response.body
    assert_match "Cancelad", response.body
  end
end

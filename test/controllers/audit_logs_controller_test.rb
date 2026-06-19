require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(role: :admin, force_password_change: false)
    sign_in @admin
  end

  test "resource_history for a DeliveryPlan includes DeliveryEvent entries from its deliveries" do
    plan = delivery_plans(:one)
    delivery = delivery_plan_assignments(:one).delivery
    DeliveryEvent.record(delivery: delivery, action: "delivered", actor: @admin)

    get resource_history_audit_logs_path(item_type: "DeliveryPlan", item_id: plan.id)

    assert_response :success
    assert_includes @response.body, "Marcada como entregada"
  end

  test "resource_history for a Delivery includes PlanEvent entries from its current plan" do
    assignment = delivery_plan_assignments(:one)
    plan = assignment.delivery_plan
    plan.start!

    get resource_history_audit_logs_path(item_type: "Delivery", item_id: assignment.delivery_id)

    assert_response :success
    assert_includes @response.body, "Plan iniciado"
  end

  test "index events tab includes both DeliveryEvent and PlanEvent in one combined feed" do
    delivery = delivery_plan_assignments(:one).delivery
    DeliveryEvent.record(delivery: delivery, action: "delivered", actor: @admin)
    delivery_plans(:one).abort!

    get audit_logs_path(tab: "events")

    assert_response :success
    assert_includes @response.body, "Marcada como entregada"
    assert_includes @response.body, "Abortado"
  end

  test "index events tab filters by delivery_plan_id" do
    other_plan = DeliveryPlan.create!(week: "45", year: 2026, status: :draft)

    get audit_logs_path(tab: "events", delivery_plan_id: other_plan.id)

    assert_response :success
    assert_includes @response.body, "Plan creado"
    refute_includes @response.body, "Abortado"
  end

  test "resource_history for a DeliveryItem links 'Ver registro' to its parent Delivery, not to the item's own (template-less) show action" do
    item = delivery_items(:one)

    get resource_history_audit_logs_path(item_type: "DeliveryItem", item_id: item.id)

    assert_response :success
    assert_includes @response.body, delivery_path(item.delivery, anchor: ActionView::RecordIdentifier.dom_id(item))
    refute_includes @response.body, "/delivery_items/#{item.id}\""
  end
end

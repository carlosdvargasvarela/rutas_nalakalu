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
end

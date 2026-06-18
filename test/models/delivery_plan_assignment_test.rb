require "test_helper"

class DeliveryPlanAssignmentTest < ActiveSupport::TestCase
  test "creating an assignment records a stop_added PlanEvent on its plan" do
    plan = DeliveryPlan.create!(week: "30", year: 2026, status: :draft)
    delivery = deliveries(:one)
    delivery.update!(status: :scheduled)

    assert_difference -> { plan.plan_events.where(action: "stop_added").count }, 1 do
      plan.delivery_plan_assignments.create!(delivery: delivery)
    end

    event = plan.plan_events.where(action: "stop_added").last
    assert_equal delivery.id, event.payload_data["delivery_id"]
  end

  test "destroying an assignment records a stop_removed PlanEvent on its plan" do
    assignment = delivery_plan_assignments(:one)
    plan = assignment.delivery_plan

    assert_difference -> { plan.plan_events.where(action: "stop_removed").count }, 1 do
      assignment.destroy!
    end
  end
end

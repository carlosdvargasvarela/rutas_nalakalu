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

  test "start! moves the delivery to in_route via update! (PaperTrail visible) and records a route_started DeliveryEvent" do
    assignment = delivery_plan_assignments(:one)
    assignment.delivery.update!(status: :ready_to_deliver)
    assignment.delivery.delivery_items.each { |i| i.update!(status: :in_plan) }
    versions_before = PaperTrail::Version.where(item_type: "Delivery", item_id: assignment.delivery.id).count

    assert_difference -> { DeliveryEvent.where(action: "route_started").count }, 1 do
      assignment.start!
    end

    assert_equal "in_route", assignment.delivery.reload.status
    assert_operator PaperTrail::Version.where(item_type: "Delivery", item_id: assignment.delivery.id).count, :>, versions_before
  end

  test "start! leaves a PaperTrail version on each item moved from in_plan to in_route" do
    assignment = delivery_plan_assignments(:one)
    assignment.delivery.update!(status: :in_plan)
    item = assignment.delivery.delivery_items.first
    item.update!(status: :in_plan)

    assert_difference -> { PaperTrail::Version.where(item_type: "DeliveryItem", item_id: item.id).count }, 1 do
      assignment.start!
    end

    assert_equal "in_route", item.reload.status
  end
end

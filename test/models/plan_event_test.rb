require "test_helper"

class PlanEventTest < ActiveSupport::TestCase
  test "record creates an event with the given action, actor and payload" do
    event = PlanEvent.record(
      delivery_plan: delivery_plans(:one),
      action: "started",
      actor: users(:one),
      payload: {note: "ok"}
    )

    assert event.persisted?
    assert_equal "started", event.action
    assert_equal users(:one).id, event.actor_id
    assert_equal({"note" => "ok"}, event.payload_data)
  end

  test "record returns nil and does not raise when creation fails" do
    result = PlanEvent.record(delivery_plan: nil, action: "started")

    assert_nil result
  end

  test "label color and icon are looked up from the action dictionaries" do
    event = PlanEvent.new(action: "aborted")

    assert_equal "Abortado", event.label
    assert_equal "danger", event.color
    assert_equal "bi-x-circle", event.icon
  end

  test "destroying the delivery_plan destroys its plan_events" do
    plan = DeliveryPlan.create!(week: "12", year: 2026, status: :draft)
    PlanEvent.record(delivery_plan: plan, action: "created")

    assert_difference -> { PlanEvent.count }, -(plan.plan_events.count) do
      plan.destroy!
    end
  end
end

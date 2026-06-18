require "test_helper"

class DeliveryEventTest < ActiveSupport::TestCase
  test "record creates an event with the given action, actor and payload" do
    event = DeliveryEvent.record(
      delivery: deliveries(:one),
      action: "approved",
      actor: users(:one),
      payload: {note: "ok"}
    )

    assert event.persisted?
    assert_equal "approved", event.action
    assert_equal users(:one).id, event.actor_id
    assert_equal({"note" => "ok"}, event.payload_data)
  end

  test "record returns nil and does not raise when creation fails" do
    result = DeliveryEvent.record(delivery: nil, action: "approved")

    assert_nil result
  end

  test "label falls back to humanized action for unknown actions" do
    event = DeliveryEvent.new(action: "some_unmapped_action")

    assert_equal "Some unmapped action", event.label
  end

  test "actor_name falls back to Sistema when there is no actor" do
    event = DeliveryEvent.new(action: "created", actor: nil)

    assert_equal "Sistema", event.actor_name
  end

  test "payload_data returns an empty hash for invalid JSON" do
    event = DeliveryEvent.new(action: "created", payload: "not json")

    assert_equal({}, event.payload_data)
  end

  test "recent orders by created_at desc" do
    older = DeliveryEvent.record(delivery: deliveries(:one), action: "created", payload: {})
    older.update_column(:created_at, 2.days.ago)
    newer = DeliveryEvent.record(delivery: deliveries(:one), action: "updated", payload: {})
    newer.update_column(:created_at, 1.day.ago)

    assert_equal [newer, older], DeliveryEvent.where(id: [older.id, newer.id]).recent.to_a
  end
end

require "test_helper"

class PlanEventsHelperTest < ActionView::TestCase
  include PlanEventsHelper

  test "describes a started event" do
    event = PlanEvent.new(action: "started")
    assert_equal "Plan iniciado", plan_event_description(event)
  end

  test "describes a stop_added event using the payload label" do
    event = PlanEvent.new(action: "stop_added", payload: {delivery_id: 5, delivery_label: "Pedido 123 — Calle Falsa 45"}.to_json)
    assert_equal "Parada agregada: Pedido 123 — Calle Falsa 45", plan_event_description(event)
  end

  test "falls back to the delivery id when there is no label in the payload" do
    event = PlanEvent.new(action: "stop_removed", payload: {delivery_id: 5}.to_json)
    assert_equal "Parada quitada: Entrega #5", plan_event_description(event)
  end
end

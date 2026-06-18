require "test_helper"

class DeliveryEventsHelperTest < ActionView::TestCase
  include DeliveryEventsHelper

  test "describes a route_started event" do
    event = DeliveryEvent.new(action: "route_started", payload: {delivery_plan_id: 5, stop_order: 2}.to_json)

    assert_equal "Entrega en ruta (parada del plan iniciada)", delivery_event_description(event)
  end

  test "describes a failed event with reason and new delivery id" do
    event = DeliveryEvent.new(
      action: "failed",
      payload: {reason: "Cliente no se encontraba", new_delivery_id: 99}.to_json
    )

    assert_equal "Entrega fracasada — Cliente no se encontraba (Reagendada: Entrega #99)", delivery_event_description(event)
  end

  test "describes a failed event without a reason" do
    event = DeliveryEvent.new(action: "failed", payload: {}.to_json)

    assert_equal "Entrega fracasada", delivery_event_description(event)
  end
end

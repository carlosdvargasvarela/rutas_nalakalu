require "test_helper"

class DeliveryPlanLocationTest < ActiveSupport::TestCase
  test "belongs to recorded_by, optional" do
    loc = DeliveryPlanLocation.new(
      delivery_plan: delivery_plans(:one),
      latitude: 9.9341,
      longitude: -84.0875,
      captured_at: Time.current,
      source: "batch",
      recorded_by: users(:one)
    )

    assert loc.valid?
    assert_equal users(:one), loc.recorded_by
  end

  test "recorded_by is optional" do
    loc = DeliveryPlanLocation.new(
      delivery_plan: delivery_plans(:one),
      latitude: 9.9341,
      longitude: -84.0875,
      captured_at: Time.current,
      source: "batch"
    )

    assert loc.valid?
    assert_nil loc.recorded_by
  end
end

require "test_helper"

class DeliveryPlanAssignmentPolicyTest < ActiveSupport::TestCase
  test "logistics can destroy a normal assignment but not a cancelled/rescheduled one, admin can always" do
    assignment = delivery_plan_assignments(:one)
    logistics = users(:one)
    logistics.update!(role: :logistics)
    admin = users(:two)
    admin.update!(role: :admin)

    assignment.delivery.update_columns(status: Delivery.statuses[:scheduled])
    assert DeliveryPlanAssignmentPolicy.new(logistics, assignment).destroy?

    assignment.delivery.update_columns(status: Delivery.statuses[:cancelled])
    refute DeliveryPlanAssignmentPolicy.new(logistics, assignment).destroy?
    assert DeliveryPlanAssignmentPolicy.new(admin, assignment).destroy?

    assignment.delivery.update_columns(status: Delivery.statuses[:rescheduled])
    refute DeliveryPlanAssignmentPolicy.new(logistics, assignment).destroy?
    assert DeliveryPlanAssignmentPolicy.new(admin, assignment).destroy?
  end
end

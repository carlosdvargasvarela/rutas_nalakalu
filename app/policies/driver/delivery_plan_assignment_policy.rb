# app/policies/driver/assignment_policy.rb
module Driver
  class DeliveryPlanAssignmentPolicy < ApplicationPolicy
    def complete?
      user.driver? && record.delivery_plan.driver_id == user.id
    end

    def fail?
      complete?
    end

    def add_note?
      complete?
    end
  end
end
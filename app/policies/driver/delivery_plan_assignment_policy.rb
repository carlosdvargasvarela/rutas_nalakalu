# app/policies/driver/assignment_policy.rb
module Driver
  class DeliveryPlanAssignmentPolicy < ApplicationPolicy
    def complete?
      user.driver?
    end

    def fail?
      complete?
    end

    def add_note?
      complete?
    end
  end
end
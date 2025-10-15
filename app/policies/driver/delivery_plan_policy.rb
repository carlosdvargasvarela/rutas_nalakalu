# app/policies/driver/delivery_plan_policy.rb
module Driver
  class DeliveryPlanPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        if user.admin?
          scope.all
        elsif user.driver?
          scope.where(driver_id: user.id)
        else
          scope.none
        end
      end
    end

    def index?
      user.driver? || user.admin?
    end

    def show?
      user.admin? || (user.driver? && record.driver_id == user.id)
    end

    def update_position?
      show?
    end
  end
end

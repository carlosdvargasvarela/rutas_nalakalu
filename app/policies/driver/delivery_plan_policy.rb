# app/policies/driver/delivery_plan_policy.rb
module Driver
  class DeliveryPlanPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        if user.driver?
          scope.where(driver_id: user.id)
        else
          scope.none
        end
      end
    end

    def index?
      user.driver?
    end

    def show?
      user.driver?
    end

    def start?
      show? && record.status_routes_created?
    end

    def finish?
      show? && record.status_in_progress?
    end

    def abort?
      show? && (record.status_routes_created? || record.status_in_progress?)
    end

    def update_position?
      show? && record.status_in_progress?
    end

    def update_position_batch?
      update_position?
    end
  end
end

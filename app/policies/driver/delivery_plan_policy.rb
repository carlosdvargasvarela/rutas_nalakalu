# frozen_string_literal: true

module Driver
  class DeliveryPlanPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present? && record.driver_id == user.id
    end

    def update_position?
      show?
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

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.where(driver_id: user.id)
      end
    end
  end
end

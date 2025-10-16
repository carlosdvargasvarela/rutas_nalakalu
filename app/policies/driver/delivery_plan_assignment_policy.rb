# frozen_string_literal: true

module Driver
  class DeliveryPlanAssignmentPolicy < ApplicationPolicy
    def start?
      belongs_to_driver? && record.pending?
    end

    def complete?
      belongs_to_driver? && record.en_route?
    end

    def mark_failed?
      belongs_to_driver? && (record.pending? || record.en_route?)
    end

    def note?
      belongs_to_driver?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        # Asignments cuyo plan pertenece al chofer autenticado
        scope.joins(:delivery_plan).where(delivery_plans: { driver_id: user.id })
      end
    end

    private

    def belongs_to_driver?
      user.present? && record.delivery_plan.driver_id == user.id
    end
  end
end

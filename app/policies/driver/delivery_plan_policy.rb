class Driver::DeliveryPlanPolicy < ApplicationPolicy
  def show?
    user.admin? || record.driver_id == user.id
  end

  def start_route?
    show?
  end

  def assignment_action?
    show?
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(driver_id: user.id)
      end
    end
  end
end

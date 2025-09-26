# app/policies/delivery_policy.rb
class DeliveryPolicy < ApplicationPolicy
  def index?
    user.admin? || user.production_manager? || user.logistics? || user.seller? || user.driver?
  end

  def show?
    return true if user.admin? || user.production_manager? || user.logistics? || user.seller?
    return true if user.driver? && record.delivery_plan&.driver_id == user.id
    false
  end

  def edit?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def update?
    edit?
  end

  def create?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def destroy?
    user.admin?
  end

  def new_internal_delivery?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def new_service_case?
    user.admin? || user.logistics? || user.production_manager? || user.seller?
  end

  def approve?
    user.admin? || user.logistics? || user.production_manager?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      elsif user.seller?
        scope.joins(order: :seller).where(sellers: { user_id: user.id })
      elsif user.driver?
        # Solo entregas asignadas a planes donde el driver es el usuario actual
        scope.joins(delivery_plan_assignments: { delivery_plan: :driver })
             .where(delivery_plans: { driver_id: user.id })
      else
        scope.none
      end
    end
  end
end

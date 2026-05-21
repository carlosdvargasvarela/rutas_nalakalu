class UserPolicy < ApplicationPolicy
  def index?
    user.admin? || user.manager?
  end

  def show?
    user.admin? || user.manager?
  end

  def edit?
    user.admin? || user.manager?
  end

  def create?
    user.admin?
  end

  def update?
    user.admin? || user.manager?
  end

  def destroy?
    user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin? || user.production_manager? || user.logistics?
        scope.all
      elsif user.seller?
        scope.joins(order: :seller).where(sellers: {user_id: user.id})
      elsif user.driver?
        # Solo entregas asignadas a planes donde el driver es el usuario actual
        scope.joins(delivery_plan_assignments: {delivery_plan: :driver})
          .where(delivery_plans: {driver_id: user.id})
      else
        scope.none
      end
    end
  end
end
